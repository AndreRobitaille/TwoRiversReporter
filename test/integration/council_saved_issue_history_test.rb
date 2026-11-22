require "test_helper"
require "minitest/mock"
require_relative "../support/council_issue_scenario"

class CouncilSavedIssueHistoryTest < ActionDispatch::IntegrationTest
  include CouncilIssueScenario

  setup do
    setup_issue_updates
    @summary = @update_meeting.meeting_summaries.create!(summary_type: "minutes_recap", content: "Saved meeting recap",
      generation_data: summary_data("The renovation still requires a grant; construction has not begun."))
    clear_enqueued_jobs
  end

  test "existing shared minutes analysis reaches both profiles without extraction and a later recap update is visible" do
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Saved meeting analysis must not be analyzed again" }) do
      assert_no_difference [ "Vote.count", "CouncilIssueReview.count", "CouncilIssueRequest.count", "CouncilAiReservation.count" ] do
        [ @member, @peer ].each do |member|
          get member_path(member)
          assert_response :success
          assert_select "#issue-updates [data-issue-update]", count: 1
          assert_select "#issue-updates", text: /construction has not begun/
          assert_select "#issue-updates a[href=?]", @document.source_url
          assert_select "#issue-updates blockquote", count: 0
          assert_select "#issue-updates", text: /#{Regexp.escape(member.name)}/, count: 0
        end
        @summary.update!(generation_data: summary_data("The path repairs are complete; the renovation is still awaiting funding."))
        get member_path(@peer)
        assert_select "#issue-updates", text: /path repairs are complete/
        assert_not_includes response.body, "construction has not begun"
      end
    end
  end

  test "preview or stale source evidence and out of service updates are excluded after proving the allowed recap" do
    get member_path(@member)
    assert_select "#issue-updates", count: 1
    @summary.update!(summary_type: "packet_analysis")
    get member_path(@member)
    assert_select "#issue-updates", count: 0
    @summary.update!(summary_type: "minutes_recap")
    @document.update!(extracted_text: "A corrected official record.")
    get member_path(@member)
    assert_select "#issue-updates", count: 0
    @summary.reload.update!(generation_data: summary_data("The source has been corrected."), evidence_withdrawn_at: nil)
    get member_path(@member)
    assert_select "#issue-updates", text: /source has been corrected/
    @update_meeting.update!(starts_at: @period.started_on - 1.day)
    get member_path(@member)
    assert_select "#issue-updates", count: 0
  end

  test "saved issue history follows the existing generated-content access boundary" do
    get member_path(@member)
    assert_select "#issue-updates", text: /construction has not begun/
    SiteSetting.instance.update!(access_mode: "gated")
    get member_path(@member)
    assert_response :success
    assert_select "#issue-updates", count: 0
    assert_not_includes response.body, "construction has not begun"
  end

  test "the separate issue history keeps all updates across pages and checks access on each page" do
    data = @summary.generation_data.deep_dup
    25.times do |n|
      item = @update_meeting.agenda_items.create!(title: "Park project #{n}", number: "6.#{n}")
      item.topics << @topic
      data.fetch("item_details") << data.fetch("item_details").first.merge(
        "agenda_item_id" => item.id, "agenda_item_title" => item.title, "summary" => "Update for park project #{n}.")
    end
    @summary.update!(generation_data: data)
    get issues_member_path(@member, term: @period.period_key)
    assert_select "[data-issue-update]", count: 25
    seen = css_select("[data-issue-update] > p").map(&:text)
    next_page = css_select('a[rel="next"]').first["href"]
    get next_page
    assert_select "[data-issue-update]", count: 1
    seen += css_select("[data-issue-update] > p").map(&:text)
    assert_equal data.fetch("item_details").pluck("summary").sort, seen.sort
    assert_select "a[href=?]", @document.source_url
    SiteSetting.instance.update!(access_mode: "gated")
    get next_page
    assert_select ".gate-card"
    assert_select "[data-issue-update]", count: 0
    assert_not_includes response.body, seen.last
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "older published recaps keep their meeting link without inventing a page citation" do
    data = summary_data("The renovation is awaiting funding.").except("source_catalog")
    data.fetch("item_details").first["citations"] = [ "Page 3" ]
    @summary.update!(generation_data: data)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Legacy summaries must be reused" }) do
      get member_path(@member)
      assert_select "#issue-updates", text: /renovation is awaiting funding/
      assert_select "#issue-updates a[href=?]", meeting_path(@update_meeting)
      assert_select "#issue-updates a[href=?]", @document.source_url, count: 0
      assert_select "#issue-updates blockquote", count: 0
    end
  end

  test "supplemental evidence does not duplicate the same agenda item and the saved recap never fabricates a campaign match" do
    source = CampaignSource.create!(campaign_article_attributes.merge(election_on: "2024-04-02", published_on: "2024-04-01"))
    statement = Campaigns::ExtractSource.prepare(source.current_version).campaign_statements.create!(
      member: @member, sequence: 0, status: "accepted", validated_at: Time.current, validation_method: "fixture",
      data: { "source_name" => @member.name, "question" => "What should the council do about the park?", "kind" => "position",
        "supporting_quote" => "Support park renovation", "summary" => "Support park renovation", "comparison_heading" => "Support park renovation" })
    assert_empty Campaigns::IssueEvidenceCandidates.for_member(@member, statements: [ statement ])
    stage = extract_issue_updates
    get member_path(@member)
    assert_select "#issue-updates [data-issue-update]", count: 2
    assert_select "#issue-updates", text: /construction has not begun/, count: 0
    candidates = Campaigns::IssueEvidenceCandidates.for_member(@member, statements: [ statement ])
    assert_equal 2, candidates.size
    assert_equal [ stage.id ], candidates.map { |row| row.fetch(:review).id }.uniq
  end

  test "nightly discovery compares an already analyzed project then corrects the promise when its minutes change" do
    travel_to Time.zone.local(2026, 11, 15, 23)
    @update_meeting.update!(starts_at: Time.current - 2.hours, committee: @council)
    source = CampaignSource.create!(campaign_article_attributes.merge(election_on: "2024-04-02", published_on: "2024-04-01"))
    position = Campaigns::ExtractSource.prepare(source.current_version).campaign_statements.create!(
      member: @member, sequence: 0, status: "accepted", validated_at: Time.current, validation_method: "fixture",
      data: { "source_name" => @member.name, "question" => "What should the city build?", "kind" => "priority",
        "supporting_quote" => "I want kids to try canoeing and kayaking.", "summary" => "Create youth programs for activities such as canoeing and kayaking.",
        "comparison_heading" => "Create outdoor programs for local youth" })
    @item.topics.clear
    @item.update!(title: "26-123 Waterfront contract")
    quote = "Staff reported that the Waterfront project would add two accessible kayak launches."
    @document.update!(extracted_text: "#{@item.title} #{quote}")
    data = summary_data("Staff presented a new waterfront project.").except("source_catalog")
    data["item_details"].first["citations"] = [ "Page 1" ]
    @summary.reload.update!(generation_data: data, evidence_withdrawn_at: nil)
    assert_empty position.related_topics
    assert_empty CouncilIssueReview.all
    assert_empty CampaignActionReview.all

    actor = User.create!(email_address: "nightly@example.test", admin: true, status: "active")
    model = Ai::OpenAiService.model_for_tier(PromptTemplate.find_by!(key: "match_campaign_issue_evidence").model_tier)
    scope = { "starting_on" => Date.current.iso8601, "committee_ids" => [ @council.id ], "document_types" => %w[minutes_pdf packet_pdf], "extract_packets" => false }
    CouncilAiBudgetMonth.create!(budget_month: Date.current.beginning_of_month, limit_microusd: 5_000_000,
      actor: actor, authorized_at: Time.current, authorization_basis: "Synthetic nightly comparison", live_actions: {
        "starting_on" => Date.current.iso8601, "estimate_method" => "utf8_bytes_plus_1024", "model" => model,
        "daily_limit_microusd" => 2_000_000, "request_limit_microusd" => 500_000, "max_requests_per_day" => 5,
        "max_concurrent" => 1, "max_input_tokens" => 200_000, "max_output_tokens" => 8_000, "issue_sources" => scope })

    reason = "Staff proposed two accessible kayak launches at the waterfront."
    respond_to_comparison = lambda do |parameters|
      stage = CampaignActionReview.find_by!(parameters: parameters)
      pairs = stage.context.fetch("pairs")
      assert_equal [ position.id ], pairs.map { |p| p.fetch("statement_id") }
      assert_equal "outcome", pairs.sole.fetch("evidence_kind")
      assert_includes pairs.sole.fetch("evidence").fetch("quote"), quote
      @calls << parameters
      content = { matches: [ { key: pairs.sole.fetch("key"), status: "direct", reason: reason, source_quote: quote } ] }
      { "id" => "synthetic-comparison", "model" => model, "choices" => [ { "message" => { "content" => content.to_json }, "finish_reason" => "stop" } ],
        "usage" => { "prompt_tokens" => 100, "completion_tokens" => 40, "total_tokens" => 140 } }
    end
    client = Object.new
    client.define_singleton_method(:chat) { |parameters:| respond_to_comparison.call(parameters) }
    nightly = lambda do
      # Only the city's external index and the provider transport are simulated.
      Scrapers::DiscoverMeetingsJob.stub(:run_inline!, []) do
        perform_enqueued_jobs(only: [ ReconcileCampaignSourcesJob, MatchCampaignIssueEvidenceJob ]) { Scrapers::DiscoverMeetingsJob.perform_now }
      end
    end
    OpenAI::Client.stub(:new, client) do
      2.times { nightly.call }
      assert_equal 1, @calls.size, CampaignActionReview.pluck(:status, :error_code).inspect
      get member_path(@member)
      assert_select "[data-campaign-proposal] [data-campaign-issue-evidence=outcome]", text: /proposed two accessible kayak launches/
      assert_select "[data-campaign-proposal] blockquote", text: quote
      assert_select "[data-campaign-proposal] a[href=?]", @document.source_url
      quote = "Staff corrected the plan: the grant for accessible kayak launches was withdrawn."
      reason = "The waterfront project lost the grant for its accessible kayak launches."
      @document.update!(extracted_text: quote)
      data = summary_data("Staff corrected the waterfront plan.")
      data["item_details"].first["record_passages"] = [ { "source_id" => "doc-#{@document.id}", "quote" => quote },
        { "source_id" => "doc-#{@document.id}", "quote" => "A fabricated quotation about kayak launches." } ]
      @summary.reload.update!(generation_data: data, evidence_withdrawn_at: nil)
      get member_path(@member)
      assert_select "[data-campaign-issue-evidence]", count: 0
      nightly.call
      get member_path(@member)
      assert_select "[data-campaign-proposal] [data-campaign-issue-evidence=outcome]", text: /lost the grant/
      assert_select "[data-campaign-proposal] blockquote", text: quote
      assert_select "[data-campaign-proposal]", text: /proposed two accessible kayak launches/, count: 0
      assert_equal 2, @calls.size
      assert_equal 2, CampaignActionRequest.count
      assert_equal 0, CouncilIssueRequest.count
    end
  end

  test "a packet report and a resident comment keep their own source and multiple developments on one project" do
    staff = "Staff reported that the grant for the park had been withdrawn."
    comment = "A resident asked when the park plans would be available to neighbors."
    packet = @update_meeting.meeting_documents.create!(document_type: "packet_pdf", source_url: "https://example.test/packet.pdf", extracted_text: staff)
    @document.update!(extracted_text: comment)
    data = summary_data("Staff reported on park funding.")
    data["source_catalog"] << Citations::SourceCatalog.snapshot(packet)
    data["item_details"].first["record_passages"] = [
      { "source_id" => "doc-#{packet.id}", "quote" => staff }, { "source_id" => "doc-#{@document.id}", "quote" => staff }
    ]
    data["public_input"] = [ { "summary" => "A resident asked about the park plans.", "record_passages" => [
      { "source_id" => "doc-#{@document.id}", "quote" => comment }
    ] } ]
    @summary.reload.update!(generation_data: data, evidence_withdrawn_at: nil)
    rows = CouncilProfiles::SavedRecapEvidence.for_periods([ @period ], summary_ids: [ @summary.id ])
    assert_equal [ [ packet.source_url, staff ], [ @document.source_url, comment ] ].sort,
      rows.map { |r| [ r.dig(:citation, :source_url), r.dig(:evidence, "quote") ] }.sort
    @summary.update!(evidence_withdrawn_at: Time.current)
    assert_empty CouncilProfiles::SavedRecapEvidence.for_periods([ @period ], summary_ids: [ @summary.id ])
  end

  private

  def summary_data(text)
    source = Citations::SourceCatalog.snapshot(@document)
    { "source_type" => "minutes", "framing" => "recap", "source_catalog" => [ source ], "item_details" => [
      { "agenda_item_id" => @item.id, "agenda_item_title" => @item.title, "activity_level" => "status_update", "summary" => text,
        "citations" => [ { "source_id" => source.fetch("source_id"), "location" => { "kind" => "whole_source" } } ] }
    ] }
  end
end
