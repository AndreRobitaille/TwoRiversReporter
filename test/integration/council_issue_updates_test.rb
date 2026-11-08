require "test_helper"
require "minitest/mock"
require_relative "../support/council_issue_scenario"

class CouncilIssueUpdatesTest < ActionDispatch::IntegrationTest
  include CouncilIssueScenario

  setup { setup_issue_updates }

  test "official concession source retains its conditional funding and advisory-body provenance" do
    sample = JSON.parse(Rails.root.join("test/fixtures/files/council_issue_official_sample.json").read)
    @topic.update!(name: "neshotah beach")
    @item.update!(title: "Neshotah Beach Pavilion/Concession Stand Project Update")
    @update_meeting.update!(body_name: sample.fetch("body"), starts_at: Time.zone.parse("#{sample.fetch('reported_on')} 18:00"))
    @document.update!(source_url: sample.fetch("source_url"), extracted_text: sample.fetch("text"))
    quote = "It was noted that without additional grants or sponsorships, the project cannot proceed at the proposed scope."
    stage = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    data = { "complete" => true, "updates" => [ { "agenda_item_id" => @item.id, "topic_ids" => [ @topic.id ],
      "subject" => "Neshotah Beach concession stand renovation", "status" => "unresolved", "occurred_on" => nil,
      "summary" => "Additional grants or sponsorships were still needed for the proposed renovation.", "conditions" => nil, "quote" => quote } ] }
    with_campaign_transport(content: data.to_json) do
      ExtractCouncilIssueUpdatesJob.perform_now(@document.id, budget_run_id: campaign_budget(stage: stage).id)
    end
    assert_equal "completed", stage.reload.status
    assert_equal sample.fetch("text"), stage.context.fetch("text")
    assert_includes @calls.sole.fetch(:messages).last.fetch(:content), "Advisory Recreation Board"
    get member_path(@member)
    assert_select "#issue-updates [data-issue-update=unresolved]", count: 1
    assert_select "#issue-updates [data-issue-update=completed]", count: 0
    assert_select "#issue-updates blockquote", text: quote
    assert_select "#issue-updates", text: /Reported Jan 14, 2026/
    assert_select "#issue-updates", text: /Advisory Recreation Board/
    assert_not_includes response.body, "Event date: Jan 14, 2026"
  end

  test "one no-new-vote source update reaches both members and unchanged nightly reads reuse it" do
    stage = nil
    assert_no_difference "Vote.count" do
      stage = extract_issue_updates
    end
    assert_equal "completed", stage.status
    assert_equal 2, stage.data.fetch("updates").size
    assert_equal 1, @calls.size
    assert_equal 1, stage.requests.count
    assert_equal "received", stage.requests.sole.status
    assert_equal 1, CouncilProfiles::SpendReport.call[:stages].fetch("issue_updates").fetch(:requests)
    assert_not_includes stage.context.to_json, @member.name
    Ai::OpenAiService.stub(:new, ->(*) { flunk "A shared saved update cannot trigger generation" }) do
      [ @member, @peer ].each do |member|
        get member_path(member)
        assert_response :success
        assert_select "#issue-updates [data-issue-update]", count: 2
        assert_select "[data-issue-update=unresolved]", text: /still needs a \$100,000 grant/
        assert_select "[data-issue-update=completed]", text: /separate path repairs/
        assert_select "[data-issue-update=completed]", text: /Event date: Jul 1, 2025/
        assert_select "#issue-updates a[href=?]", @document.source_url, count: 2
        assert_select "#issue-updates", text: /#{Regexp.escape(member.name)}/, count: 0
      end
      assert_no_difference [ "CouncilIssueReview.count", "CouncilIssueRequest.count", "CouncilAiReservation.count" ] do
        ReconcileCampaignSourcesJob.perform_now
        perform_enqueued_jobs(only: ExtractCouncilIssueUpdatesJob)
        ExtractCouncilIssueUpdatesJob.perform_now(@document.id)
        PromptTemplate.find_by!(key: "extract_council_issue_updates").update!(model_tier: "lightweight")
        ExtractCouncilIssueUpdatesJob.perform_now(@document.id)
      end
    end
  end

  test "source replacement removes the old update then publishes one corrected shared result without changing votes" do
    old = extract_issue_updates
    original_data = old.data
    get member_path(@member)
    assert_select "#issue-updates [data-issue-update]", count: 2
    @quote = "The park renovation grant was awarded on August 3, 2025, fully funding the planned construction; work has not begun."
    @document.update!(extracted_text: @quote)
    @update_meeting.update!(starts_at: Time.zone.parse("2025-08-04 18:00"))
    get member_path(@member)
    assert_select "#issue-updates", count: 0
    stage = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    data = issue_response
    data["updates"] = [ data["updates"].first.merge("status" => "funded", "occurred_on" => "2025-08-03",
      "summary" => "A grant fully funded the renovation; construction has not begun.") ]
    with_campaign_transport(content: data.to_json) do
      assert_no_difference "Vote.count" do
        ExtractCouncilIssueUpdatesJob.perform_now(@document.id, budget_run_id: campaign_budget(stage: stage).id)
      end
    end
    [ @member, @peer ].each do |member|
      get member_path(member)
      assert_select "#issue-updates [data-issue-update]", count: 1
      assert_select "[data-issue-update=funded]", text: /construction has not begun/
      assert_not_includes response.body, "still needs a $100,000 grant"
    end
    assert_equal original_data, old.reload.data
    assert_equal 2, @calls.size
    assert_equal 2, CouncilIssueRequest.count
    assert_equal [ "no", "yes" ], @motion.votes.order(:value).pluck(:value)
  end

  test "budget pauses before transport and nightly recovery only revisits selected sources" do
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Source selection is not spending authorization" }) do
      assert_no_enqueued_jobs(only: ExtractCouncilIssueUpdatesJob) { ReconcileCampaignSourcesJob.perform_now }
      ExtractCouncilIssueUpdatesJob.perform_now
      assert_equal 0, CouncilIssueReview.count
      ExtractCouncilIssueUpdatesJob.perform_now(@document.id)
      stage = CouncilIssueReview.sole
      assert_equal "budget_paused", stage.status
      assert_equal 0, stage.attempts
      assert_empty stage.requests
      other = @update_meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "Other unselected source", source_url: "https://example.test/other.pdf")
      ExtractCouncilIssueUpdatesJob.perform_now
      assert_equal [ @document.id ], CouncilIssueReview.pluck(:meeting_document_id)
      assert_not_equal other.id, stage.meeting_document_id
    end
    assert_equal "completed", extract_issue_updates.status
  end

  test "replaced in-flight evidence stays retained but cannot appear on a profile" do
    stage = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    budget = campaign_budget(stage: stage)
    response = issue_response.to_json
    client = Object.new
    document = @document
    client.define_singleton_method(:chat) do |parameters:|
      document.update!(extracted_text: "Corrected record: this project was not discussed.")
      { "choices" => [ { "message" => { "content" => response }, "finish_reason" => "stop" } ] }
    end
    OpenAI::Client.stub(:new, client) { ExtractCouncilIssueUpdatesJob.perform_now(@document.id, budget_run_id: budget.id) }
    assert_equal "completed", stage.reload.status
    get member_path(@member)
    assert_select "#issue-updates", count: 0
    assert_equal "received", stage.requests.sole.status
  end

  test "invented quotes invalid topic IDs incomplete output and future event dates fail bounded validation" do
    stage = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    invalid = issue_response
    invalid["updates"].first["quote"] = "The entire renovation was completed and paid for."
    with_campaign_transport(content: invalid.to_json) do
      ExtractCouncilIssueUpdatesJob.perform_now(@document.id, budget_run_id: campaign_budget(stage: stage).id)
    end
    assert_equal "failed", stage.reload.status
    invalid = issue_response.merge("complete" => false)
    with_campaign_transport(content: invalid.to_json) do
      ExtractCouncilIssueUpdatesJob.perform_now(@document.id, budget_run_id: stage.council_ai_budget_run_id)
    end
    assert_equal 2, stage.reload.attempts
    assert_equal "failed", stage.status
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Attempts cannot reset" }) { ExtractCouncilIssueUpdatesJob.perform_now }
    assert_equal 2, stage.requests.count
    invalid = issue_response
    invalid["updates"].first["topic_ids"] = [ -1 ]
    assert_raises(CouncilProfiles::IssueUpdates::InvalidResponse) { CouncilProfiles::IssueUpdates.new(stage.context).parse(invalid.to_json) }
    invalid = issue_response
    invalid["updates"].first["occurred_on"] = "2027-01-01"
    assert_raises(CouncilProfiles::IssueUpdates::InvalidResponse) { CouncilProfiles::IssueUpdates.new(stage.context).parse(invalid.to_json) }
    get member_path(@member)
    assert_select "#issue-updates", count: 0
  end

  test "an incomplete provider response retains the receipt and does not retry" do
    stage = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    with_campaign_transport(content: issue_response.to_json, finish_reason: "length") do
      ExtractCouncilIssueUpdatesJob.perform_now(@document.id, budget_run_id: campaign_budget(stage: stage).id)
    end
    assert_equal "incomplete", stage.reload.status
    assert_equal "length", stage.requests.sole.finish_reason
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Incomplete provider output needs recovery" }) { ExtractCouncilIssueUpdatesJob.perform_now }
    assert_equal 1, stage.requests.count
  end

  test "source eligibility topic governance and selected service window control later reads" do
    extract_issue_updates
    get member_path(@member)
    assert_select "#issue-updates [data-issue-update]", count: 2
    @topic.update!(status: "blocked")
    get member_path(@member)
    assert_select "#issue-updates", count: 0
    @topic.update!(status: "approved")
    get member_path(@member)
    assert_select "#issue-updates [data-issue-update]", count: 2
    get member_path(@member, term: "all")
    assert_select "#issue-updates", count: 0
    @update_meeting.update!(status: "cancelled")
    get member_path(@member)
    assert_select "#issue-updates", count: 0
    assert_equal 1, @calls.size
  end

  test "allowed users see source evidence before anonymous gating hides every representation" do
    extract_issue_updates
    SiteSetting.instance.update!(access_mode: "gated")
    sign_in_as(User.create!(email_address: "issue-reader@example.test", status: "active"))
    get member_path(@member)
    assert_select "#issue-updates [data-issue-update]", count: 2
    assert_includes response.body, @quote
    delete public_session_path
    get member_path(@member)
    assert_select "#issue-updates", count: 0
    assert_not_includes response.body, @quote
    assert_not_includes response.body, "The renovation still needs"
    get member_path(@member, format: :json)
    assert_response :not_acceptable
    assert_not_includes response.body, @quote
  end

  test "oversized sources are retained without truncation or provider calls" do
    @document.update!(extracted_text: @document.extracted_text + (" long source" * 6_000))
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Oversized input must be partitioned first" }) do
      ExtractCouncilIssueUpdatesJob.perform_now(@document.id)
    end
    stage = CouncilIssueReview.sole
    assert_equal "oversized", stage.status
    assert_equal @document.extracted_text, stage.context.fetch("text")
    assert_equal 0, stage.attempts
  end

  test "verified Google sees the same cited update and a spoofed crawler does not" do
    extract_issue_updates
    SiteSetting.instance.update!(access_mode: "gated")
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(Crawlers::IpRanges.new.cache_key(:google), { prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i })
    headers = { "User-Agent" => "Googlebot/2.1 (+http://www.google.com/bot.html)", "REMOTE_ADDR" => "66.249.66.1" }
    get member_path(@member), headers: headers
    assert_response :success
    assert_select ".gated-content #issue-updates [data-issue-update]", count: 2
    assert_includes response.body, @quote
    assert_includes response.headers["Cache-Control"], "no-store"
    get member_path(@member), headers: headers.merge("REMOTE_ADDR" => "198.51.100.42")
    assert_select "#issue-updates", count: 0
    assert_not_includes response.body, @quote
  ensure
    Rails.cache = previous_cache if previous_cache
  end
end
