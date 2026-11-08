require "test_helper"
require "minitest/mock"
require_relative "../support/council_recommendation_scenario"

class CouncilLiveSourcesTest < ActionDispatch::IntegrationTest
  include CouncilRecommendationScenario

  setup do
    setup_recommendations
    travel_to Time.zone.local(2026, 11, 8, 20)
    @motion.meeting.update!(starts_at: Time.zone.local(2026, 11, 8, 18))
    @recommendation.merge!("made_on" => Date.current.iso8601,
      "quote" => "Before the November 8 decision, City Manager Alex Manager recommended: #{@motion.description}.")
    @document.update!(extracted_text: @recommendation["quote"])
    @actor = User.create!(email_address: "synthetic-source-allowance@example.test", admin: true, status: "active")
    @stage = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    @estimate = Campaigns::CostPreflight.for_stage(@stage)
  end

  test "missing authorization holds and an explicit source scope enables nightly reuse" do
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Missing authorization cannot authorize source extraction" }) do
      ExtractCouncilIssueUpdatesJob.perform_now
    end
    assert_equal "missing_budget", @stage.reload.error_code
    assert_equal 0, @stage.attempts
    assert_empty @stage.requests
    month = authorize_sources
    clear_enqueued_jobs
    assert_enqueued_with(job: ExtractCouncilIssueUpdatesJob) { ReconcileCampaignSourcesJob.perform_now }
    with_source_transport { perform_enqueued_jobs(only: ExtractCouncilIssueUpdatesJob) }
    assert_equal "completed", @stage.reload.status
    assert_equal 1, @calls.size
    assert_equal 1, @stage.data.fetch("recommendations").size
    assert_equal month.id, @stage.council_ai_budget_run.live_budget_month_id
    assert_equal @estimate.fetch(:cost_microusd), month.reserved_microusd
    [ @member, @peer ].each do |member|
      get member_path(member)
      assert_select "#staff-recommendations", count: 1
    end
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Unchanged source and page reuse must be free" }) do
      assert_no_difference [ "CouncilIssueReview.count", "CouncilIssueRequest.count", "CouncilAiBudgetRun.count", "CouncilAiReservation.count" ] do
        2.times { ExtractCouncilIssueUpdatesJob.perform_now }
        get member_path(@member)
      end
    end
  end

  test "discovery admits only registered bodies source types and future window without a historical sweep" do
    authorize_sources
    prior = source_document(date: Date.current - 1)
    foreign = source_document(date: Date.current, committee: Committee.create!(name: "Unregistered Board", slug: "unregistered-board"))
    unsupported = source_document(date: Date.current, type: "minutes_html")
    future = source_document(date: Date.current + 1)
    fresh = source_document(date: Date.current)
    with_source_transport { ExtractCouncilIssueUpdatesJob.perform_now }
    assert_equal 2, @calls.size
    assert_equal [ @document.id, fresh.id ].sort, CouncilIssueReview.pluck(:meeting_document_id).sort
    assert_empty CouncilIssueReview.where(meeting_document_id: [ prior.id, foreign.id, unsupported.id, future.id ])
    assert_equal "completed", CouncilIssueReview.find_by!(meeting_document: fresh).status
    assert_equal 2, CouncilProfiles::SpendReport.call[:stages].fetch("issue_updates").fetch(:requests)
  end

  test "minutes reuse the normal meeting workflow even when an older source scope includes them" do
    month = authorize_sources(scope: source_scope.merge("document_types" => %w[minutes_pdf packet_pdf]))
    minutes = source_document(date: Date.current, type: "minutes_pdf")
    assert_includes CouncilProfiles::LiveSources.documents, @document
    assert_not_includes CouncilProfiles::LiveSources.documents, minutes
    with_source_transport { ExtractCouncilIssueUpdatesJob.perform_now }
    assert_equal 1, @calls.size
    assert_not CouncilIssueReview.exists?(meeting_document: minutes)
    # A formerly selected minutes stage cannot borrow recurring source allowance.
    stage = CouncilProfiles::ExtractIssueUpdates.prepare(minutes)
    with_source_transport { ExtractCouncilIssueUpdatesJob.perform_now(minutes.id) }
    assert_equal "outside_live_source_scope", stage.reload.error_code
    assert_equal 1, @calls.size
    assert_equal 1, month.reservations.count
  end

  test "changed source pauses when the shared monthly limit is spent without resetting counts" do
    month = authorize_sources(limit: @estimate.fetch(:cost_microusd))
    with_source_transport { ExtractCouncilIssueUpdatesJob.perform_now }
    @document.update!(extracted_text: @document.extracted_text + "\nA corrected public source version.")
    with_source_transport { ExtractCouncilIssueUpdatesJob.perform_now }
    replacement = CouncilIssueReview.order(:id).last
    assert_equal "monthly_budget_limit", replacement.error_code
    assert_equal 0, replacement.attempts
    assert_equal 1, @calls.size
    assert_empty replacement.requests
    get member_path(@member)
    assert_select "#staff-recommendations", count: 0
    travel_to Time.zone.local(2026, 11, 9, 20)
    assert_no_difference("Vote.count") { with_source_transport { ExtractCouncilIssueUpdatesJob.perform_now } }
    assert_equal "monthly_budget_limit", replacement.reload.error_code
    assert_equal 1, @calls.size
    assert_equal 1, month.reservations.count
  end

  test "source-specific windows cannot borrow a historical campaign window or broaden scope on renewal" do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      authorize_sources(scope: source_scope.merge("starting_on" => "2024-04-01"))
    end
    assert_includes error.message, "historical source channels"
    authorize_sources
    travel_to Time.zone.local(2026, 12, 1, 20)
    renewal = authorize_sources(starting_on: "2026-11-08", scope: source_scope.merge("starting_on" => "2026-11-08"))
    assert_equal "2026-11-08", renewal.live_actions.dig("issue_sources", "starting_on")
    assert_not renewal.update(live_actions: renewal.live_actions.deep_merge("issue_sources" => { "document_types" => %w[packet_pdf minutes_pdf] }))
    assert_includes renewal.errors.full_messages.join, "historical source channels"
    assert_empty @calls
  end

  test "revoked scopes exhausted retries and disabled new months do not dispatch" do
    month = authorize_sources
    3.times { with_source_transport(content: "invalid JSON") { ExtractCouncilIssueUpdatesJob.perform_now } }
    assert_equal 2, @calls.size
    assert_equal 2, @stage.reload.attempts
    fresh = source_document(date: Date.current)
    month.update!(revoked_at: Time.current)
    assert_empty CouncilProfiles::LiveSources.documents
    with_source_transport { ExtractCouncilIssueUpdatesJob.perform_now(fresh.id) }
    assert_equal "monthly_budget_revoked", CouncilIssueReview.find_by!(meeting_document: fresh).error_code
    travel_to Time.zone.local(2026, 12, 1, 20)
    assert_not CouncilProfiles::LiveSources.enabled?
    with_source_transport { ExtractCouncilIssueUpdatesJob.perform_now }
    assert_equal 2, @calls.size
  end

  test "authorization is retained and revocation after run creation is enforced at dispatch" do
    month = authorize_sources
    run = CouncilProfiles::LiveBudget.call(@stage)
    assert run
    assert_not month.update(live_actions: month.live_actions.except("issue_sources"))
    month.reload.update!(revoked_at: Time.current)
    with_source_transport { CouncilProfiles::ExtractIssueUpdates.call(@stage, budget_run: run) }
    assert_equal "monthly_budget_revoked", @stage.reload.error_code
    assert_empty @calls
    assert_empty month.reservations
  end

  test "legacy action-only policy does not authorize an explicitly selected official source" do
    authorize_sources(scope: nil)
    with_source_transport { ExtractCouncilIssueUpdatesJob.perform_now(@document.id) }
    assert_equal "outside_live_source_scope", @stage.reload.error_code
    assert_equal 0, @stage.attempts
    assert_empty @calls
    assert_empty CouncilProfiles::LiveSources.documents
  end

  test "daily paused source recovery resumes under the same monthly policy on the next day" do
    month = authorize_sources(max_requests: 1)
    with_source_transport { ExtractCouncilIssueUpdatesJob.perform_now }
    @document.update!(extracted_text: @document.extracted_text + "\nA corrected public source version.")
    with_source_transport { ExtractCouncilIssueUpdatesJob.perform_now }
    replacement = CouncilIssueReview.order(:id).last
    assert_equal "live_daily_request_limit", replacement.error_code
    assert_equal 1, @calls.size
    travel_to Time.zone.local(2026, 11, 9, 20)
    assert_no_difference("Vote.count") { with_source_transport { ExtractCouncilIssueUpdatesJob.perform_now } }
    assert_equal "completed", replacement.reload.status
    assert_equal 2, @calls.size
    assert_equal 2, month.reservations.count
    get member_path(@member)
    assert_select "#staff-recommendations", count: 1
  end

  test "topic extraction queues the newly eligible source and the resulting evidence reaches the member" do
    authorize_sources
    @item.topics.delete(@topic)
    assert_nil CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    ai = Minitest::Mock.new
    ai.expect(:extract_topics, { items: [ { id: @item.id, category: "Recreation", tags: [ @topic.name ], confidence: 1.0 } ] }.to_json) do |*|
      true
    end
    retrieval = Object.new
    def retrieval.retrieve_context(*) = []
    def retrieval.format_context(*) = ""
    clear_enqueued_jobs
    assert_enqueued_with(job: ExtractCouncilIssueUpdatesJob, args: [ { meeting_id: @motion.meeting_id } ]) do
      RetrievalService.stub(:new, retrieval) do
        Ai::OpenAiService.stub(:new, ai) { ExtractTopicsJob.perform_now(@motion.meeting_id) }
      end
    end
    ai.verify
    assert_equal [ @topic.id ], @item.reload.topic_ids
    with_source_transport { perform_enqueued_jobs(only: ExtractCouncilIssueUpdatesJob) }
    assert_equal "completed", @stage.reload.status
    assert_equal 1, @calls.size
    get member_path(@member)
    assert_select "#staff-recommendations", count: 1
  end

  private

  def source_scope
    { "starting_on" => Date.current.iso8601, "committee_ids" => [ @council.id ], "document_types" => [ "packet_pdf" ] }
  end

  def authorize_sources(limit: 5_000_000, starting_on: Date.current.iso8601, scope: source_scope, max_requests: 10)
    policy = { "starting_on" => starting_on, "estimate_method" => "utf8_bytes_plus_1024",
      "model" => @stage.parameters.fetch("model"), "daily_limit_microusd" => 2_000_000,
      "request_limit_microusd" => 500_000, "max_requests_per_day" => max_requests, "max_concurrent" => 1,
      "max_input_tokens" => 200_000, "max_output_tokens" => 8_000 }
    policy["issue_sources"] = scope if scope
    CouncilAiBudgetMonth.create!(budget_month: Date.current.beginning_of_month, limit_microusd: limit,
      actor: @actor, authorized_at: Time.current, authorization_basis: "Synthetic source-channel allowance only", live_actions: policy)
  end

  def source_document(date:, committee: @council, type: "packet_pdf")
    meeting = council_meeting(date.iso8601, committee: committee)
    item = meeting.agenda_items.create!(title: "Park renovation")
    item.topics << @topic
    meeting.meeting_documents.create!(document_type: type, source_url: "https://example.test/source-#{meeting.id}.pdf",
      extracted_text: "City Staff recommended reviewing the park plan before any funding decision.")
  end

  def with_source_transport(content: nil, &block)
    data = { complete: true, updates: [], actions: [], recommendations: [] }
    # The original document has one attributed recommendation. Other channel
    # fixtures deliberately contain no supported complete proposal to compare.
    response_for = lambda do |parameters|
      stage = CouncilIssueReview.find_by!(parameters: parameters)
      content || data.merge(recommendations: stage.meeting_document_id == @document.id ? [ @recommendation ] : []).to_json
    end
    calls = @calls
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      calls << parameters
      { "id" => "synthetic-source-response", "model" => parameters.fetch(:model),
        "choices" => [ { "message" => { "content" => response_for.call(parameters) }, "finish_reason" => "stop" } ],
        "usage" => { "prompt_tokens" => 100, "completion_tokens" => 100, "total_tokens" => 200 } }
    end
    OpenAI::Client.stub(:new, client, &block)
  end
end
