require "test_helper"
require "minitest/mock"
require_relative "../support/council_action_scenario"

class CouncilRecordedActionsTest < ActionDispatch::IntegrationTest
  include CouncilActionScenario

  setup { setup_recorded_actions }

  test "one shared call preserves distinct actions and outcomes without requiring a vote" do
    @motion.destroy!
    stage = nil
    assert_no_difference([ "Vote.count", "Member.count", "MemberAlias.count" ]) { stage = extract_recorded_actions }
    assert_equal "completed", stage.status
    assert_equal 2, stage.data.fetch("actions").size
    assert_equal 2, stage.data.fetch("updates").size
    assert_equal 1, @calls.size
    assert_equal 1, stage.requests.count
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Saved advocacy and nightly reuse must not call AI" }) do
      get member_path(@member)
      assert_select "#recorded-actions [data-recorded-action=proposal]", count: 1
      assert_select "#recorded-actions", text: /received no second/
      assert_select "#recorded-actions [data-recorded-action=analysis_request]", count: 0
      get member_path(@peer)
      assert_select "#recorded-actions [data-recorded-action=analysis_request]", count: 1
      assert_select "#recorded-actions", text: /accessible park entrances/
      assert_select "#recorded-actions [data-recorded-action=proposal]", count: 0
      assert_no_difference "CouncilIssueReview.count" do
        ExtractCouncilIssueUpdatesJob.perform_now
        PromptTemplate.find_by!(key: "extract_council_issue_updates").update!(model_tier: "lightweight")
        ExtractCouncilIssueUpdatesJob.perform_now
      end
    end
  end

  test "unknown and ambiguous source names stay retained until an existing identity resolves them" do
    data = action_response
    data["actions"].first.merge!("speaker" => "Jordan Speaker", "quote" => @action_quotes.first.sub(@member.name, "Jordan Speaker"))
    @document.update!(extracted_text: @document.extracted_text.sub(@member.name, "Jordan Speaker"))
    stage = extract_recorded_actions(data)
    assert_equal 2, stage.data.fetch("actions").size
    get member_path(@member)
    assert_select "#recorded-actions", count: 0
    get member_path(@peer)
    assert_select "#recorded-actions [data-recorded-action]", count: 1
    @member.member_aliases.create!(name: "Jordan Speaker")
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Identity correction must reuse saved source evidence" }) do
      get member_path(@member)
      assert_select "#recorded-actions blockquote", text: /Jordan Speaker proposed/
      conflicting = Member.create!(name: "Jordan Speaker")
      get member_path(@member)
      assert_select "#recorded-actions", count: 0
      conflicting.destroy!
      get member_path(@member)
      assert_select "#recorded-actions [data-recorded-action]", count: 1
    end
    assert_equal 1, @calls.size
  end

  test "source corrections and service dates control later actions without changing votes" do
    stage = extract_recorded_actions
    get member_path(@member)
    assert_select "#recorded-actions [data-recorded-action]", count: 1
    @period.update!(ended_on: Date.new(2025, 7, 8), end_source_version: @source, end_page: 5)
    get member_path(@member)
    assert_select "#recorded-actions", count: 0
    @period.update!(ended_on: nil, end_source_version: nil, end_page: nil)
    @document.update!(extracted_text: @quote)
    get member_path(@member)
    assert_select "#recorded-actions", count: 0
    corrected = issue_response.merge("updates" => [ issue_response.fetch("updates").first ])
    assert_no_difference("Vote.count") { assert_equal "completed", extract_recorded_actions(corrected).status }
    get member_path(@member)
    assert_select "#recorded-actions", count: 0
    assert_select "#issue-updates [data-issue-update]", count: 1
    assert_equal 2, stage.reload.data.fetch("actions").size
    assert_equal 2, @calls.size
  end

  test "new schema does not reopen completed milestone-only evidence" do
    input = CouncilProfiles::IssueInput.new(@document)
    legacy = CouncilIssueReview.create!(meeting_document: @document, input_key: input.key, context: input.context,
      parameters: {}, status: "completed", completed_at: Time.current,
      data: CouncilProfiles::IssueUpdates.new(input.context).parse(issue_response.except("actions").to_json))
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Schema additions cannot reopen historical evidence" }) do
      assert_no_difference("CouncilIssueReview.count") { ExtractCouncilIssueUpdatesJob.perform_now(@document.id) }
      assert_equal legacy.id, CouncilProfiles::ExtractIssueUpdates.prepare(@document).id
      get member_path(@member)
      assert_select "#issue-updates [data-issue-update]", count: 2
      assert_select "#recorded-actions", count: 0
    end
  end

  test "unlocated speaker invented action and missing complete array fail validation" do
    stage = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    parser = CouncilProfiles::IssueUpdates.new(stage.context)
    invalid = action_response
    invalid["actions"].first["speaker"] = "Someone Not In The Passage"
    assert_raises(CouncilProfiles::IssueUpdates::InvalidResponse) { parser.parse(invalid.to_json) }
    invalid = action_response
    invalid["actions"].first["quote"] = "Jordan Attendance proposed an entirely different and unrecorded policy."
    assert_raises(CouncilProfiles::IssueUpdates::InvalidResponse) { parser.parse(invalid.to_json) }
    assert_raises(CouncilProfiles::IssueUpdates::InvalidResponse) { parser.parse(action_response.except("actions").to_json) }
    invalid = action_response
    invalid["actions"].first["occurred_on"] = nil
    assert_raises(CouncilProfiles::IssueUpdates::InvalidResponse) { parser.parse(invalid.to_json) }
    invalid = action_response.merge("actions" => action_response["actions"] * 21)
    assert_raises(CouncilProfiles::IssueUpdates::InvalidResponse) { parser.parse(invalid.to_json) }
  end

  test "published library discussion retains advocacy without inventing a decision or changing its date" do
    sample = JSON.parse(Rails.root.join("test/fixtures/files/council_advocacy_official_sample.json").read)
    @member.update!(name: "Mark Bittner")
    @topic.update!(name: "library funding")
    @item.update!(title: "Discussion of Draft Fiscal Year 2026 City Budget")
    @update_meeting.update!(body_name: "City Council Work Session", starts_at: Time.zone.parse("2025-11-24 18:00"))
    @document.update!(source_url: sample.fetch("source_url"), extracted_text: sample.fetch("text"))
    quote = "Councilmember Bittner advocated for reconsidering the library funding increase, noting its community importance"
    data = { "complete" => true, "updates" => [], "actions" => [
      { "agenda_item_id" => @item.id, "topic_ids" => [ @topic.id ], "speaker" => "Councilmember Bittner",
        "kind" => "follow_up", "occurred_on" => "2025-11-24", "quote" => quote,
        "summary" => "Advocated reconsidering the library funding increase; no clear consensus was reached." }
    ] }
    assert_no_difference("Vote.count") { assert_equal "completed", extract_recorded_actions(data).status }
    get member_path(@member)
    assert_select "#recorded-actions [data-recorded-action=follow_up]", count: 1
    assert_select "#recorded-actions", text: /no clear consensus/
    assert_select "#recorded-actions summary", text: "Nov 24, 2025 · Source"
    assert_select "#recorded-actions blockquote", text: quote
    assert_select "#issue-updates", count: 0
  end

  test "reporting is allowed for readers and verified Google but hidden from gated visitors" do
    extract_recorded_actions
    SiteSetting.instance.update!(access_mode: "gated")
    sign_in_as(User.create!(email_address: "action-reader@example.test", status: "active"))
    get member_path(@member)
    assert_select ".gated-content #recorded-actions [data-recorded-action]", count: 1
    assert_includes response.body, @action_quotes.first
    delete public_session_path
    get member_path(@member)
    assert_select "#recorded-actions", count: 0
    assert_not_includes response.body, @action_quotes.first
    get member_path(@member, format: :json)
    assert_response :not_acceptable
    assert_not_includes response.body, @action_quotes.first

    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(Crawlers::IpRanges.new.cache_key(:google), { prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i })
    headers = { "User-Agent" => "Googlebot/2.1 (+http://www.google.com/bot.html)", "REMOTE_ADDR" => "66.249.66.1" }
    get member_path(@member), headers: headers
    assert_select ".gated-content #recorded-actions [data-recorded-action]", count: 1
    assert_includes response.headers["Cache-Control"], "no-store"
    get member_path(@member), headers: headers.merge("REMOTE_ADDR" => "198.51.100.42")
    assert_select "#recorded-actions", count: 0
    assert_not_includes response.body, @action_quotes.first
  ensure
    Rails.cache = previous_cache if previous_cache
  end
end
