require "test_helper"
require "minitest/mock"
require_relative "../support/council_recommendation_scenario"

class CouncilStaffRecommendationsTest < ActionDispatch::IntegrationTest
  include CouncilRecommendationScenario

  setup { setup_recommendations }

  test "official concession recommendation retains collective staff attribution and every spending limit" do
    sample = JSON.parse(Rails.root.join("test/fixtures/files/council_recommendation_official_sample.json").read)
    @motion.meeting.update!(starts_at: Time.zone.parse("2025-12-01 18:00"))
    @item.update!(title: "Neshotah Beach Concession Stand - Renovation Project Funding Option")
    @motion.update!(description: sample.fetch("proposal"))
    @document.update!(source_url: sample.fetch("source_url"), extracted_text: sample.fetch("text"))
    @recommendation.merge!("author" => "City Staff", "role" => nil, "author_kind" => "unspecified_staff",
      "made_on" => sample.fetch("reported_on"), "proposal" => sample.fetch("proposal"), "quote" => sample.fetch("text"))
    stage = extract_recommendations
    assert_equal "completed", stage.status
    assert_equal sample.fetch("text"), stage.context.fetch("text")
    assert_equal [ @recommendation ], stage.data.fetch("recommendations")
    get recommendation_path
    assert_select "h2", text: "City Staff"
    assert_select "[data-recommendation-result=supported]", count: 1
    assert_select "blockquote", text: /\$520,000.*\$256,000.*\$131,000/
    assert_not_includes response.body, "Kyle Kordell"
    assert_select "a[href=?]", sample.fetch("source_url")
  end

  test "packet admission has a bounded larger input and still cannot dispatch without a budget" do
    @document.update!(extracted_text: @document.extracted_text + "\n" + "x" * 65_000)
    stage = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    assert_equal "pending", stage.status
    assert_equal 8_000, stage.parameters.fetch("max_completion_tokens")
    Ai::OpenAiService.stub(:new, ->(*) { flunk "No allowance means no paid transport" }) do
      ExtractCouncilIssueUpdatesJob.perform_now(@document.id)
      assert_equal "budget_paused", stage.reload.status
      @document.update!(extracted_text: "x" * 121_000)
      assert_equal "oversized", CouncilProfiles::ExtractIssueUpdates.prepare(@document).status
    end
  end

  test "recommendations paginate deterministically and retain the chosen term and subset" do
    rows = [ @recommendation ] + 26.times.map do |index|
      item = @motion.meeting.agenda_items.create!(title: "Street repair #{index}")
      item.topics << @topic
      motion = @motion.meeting.motions.create!(agenda_item: item, description: "Approve street repair #{index}", outcome: "passed")
      motion.votes.create!(member: @member, value: "yes")
      motion.votes.create!(member: @peer, value: "no")
      @recommendation.merge("agenda_item_id" => item.id, "proposal" => motion.description,
        "quote" => "Before the decision, City Manager Alex Manager recommended: #{motion.description}.")
    end
    @document.update!(extracted_text: rows.map { |row| row["quote"] }.join("\n"))
    assert_equal "completed", extract_recommendations(rows).status
    get recommendation_path(term: @period.period_key, subset: "divided")
    assert_select "[data-recommendation-result=supported]", count: 25
    assert_includes response.body, "27 of 27 comparable votes"
    assert_select ".member-vote-pages a[href*=page]" do |links|
      assert links.all? { |link| link["href"].include?("term=#{@period.period_key}") && link["href"].include?("subset=divided") }
    end
    get recommendation_path(term: @period.period_key, subset: "divided", page: 2)
    assert_select "[data-recommendation-result=supported]", count: 2
    assert_select "blockquote", text: @recommendation["quote"]
  end

  test "one source feeds both members and page views and nightly reuse make no calls" do
    stage = extract_recommendations
    assert_equal "completed", stage.status
    assert_equal [ @recommendation ], stage.data.fetch("recommendations")
    assert_equal 1, @calls.size
    assert_equal 1, stage.requests.count
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Saved recommendation reads cannot call AI" }) do
      [ [ @member, 1 ], [ @peer, 0 ] ].each do |member, supported|
        get member_path(member)
        assert_select "#staff-recommendations:not([open])", count: 1
        assert_select "#staff-recommendations", text: /Alex Manager/
        get recommendation_path(member)
        assert_response :success
        assert_includes response.body, "#{supported} of 1 comparable votes"
        assert_select "[data-recommendation-result]", count: 1
        assert_select "blockquote", text: @recommendation.fetch("quote")
      end
      assert_no_difference [ "CouncilIssueReview.count", "CouncilIssueRequest.count", "CouncilAiReservation.count" ] do
        ExtractCouncilIssueUpdatesJob.perform_now
        PromptTemplate.find_by!(key: "extract_council_issue_updates").update!(model_tier: "lightweight")
        ExtractCouncilIssueUpdatesJob.perform_now(@document.id)
      end
    end
  end

  test "a yes vote to reject supports the rejection recommendation and opposition reverses the comparison" do
    @motion.update!(description: "Reject the proposed parking fee increase")
    @recommendation.merge!("proposal" => @motion.description,
      "quote" => "Before the decision, City Manager Alex Manager recommended: #{@motion.description}.")
    @document.update!(extracted_text: @recommendation.fetch("quote"))
    extract_recommendations
    assert_equal 1, recommendation_report.groups.sole.fetch(:supported)
    assert_equal 0, recommendation_report(@peer).groups.sole.fetch(:supported)
    @recommendation.merge!("position" => "oppose", "quote" => "Before the decision, City Manager Alex Manager opposed the proposal: #{@motion.description}.")
    @document.update!(extracted_text: @recommendation.fetch("quote"))
    assert_no_difference("Vote.count") { extract_recommendations }
    assert_equal 0, recommendation_report.groups.sole.fetch(:supported)
    assert_equal 1, recommendation_report(@peer).groups.sole.fetch(:supported)
  end

  test "different wording additional conditions multiple motions and uncertain timing remain excluded" do
    extract_recommendations
    assert_equal 1, recommendation_report.groups.sole.fetch(:compared)
    original = @motion.description
    @motion.update!(description: original + " with an increased spending cap")
    assert_match(/wording differs/, recommendation_report.groups.sole.fetch(:rows).sole.fetch(:excluded))
    @motion.update!(description: original)
    amendment = @motion.meeting.motions.create!(agenda_item: @item, description: "Amend the proposed spending cap", outcome: "failed")
    assert recommendation_report.groups.sole.fetch(:rows).all? { |row| row[:excluded].include?("Multiple motions") }
    amendment.destroy!
    @recommendation["timing"] = "unclear"
    @document.update!(extracted_text: @document.extracted_text + "\nTiming remains unclear.")
    extract_recommendations
    assert_match(/timing/, recommendation_report.groups.sole.fetch(:rows).sole.fetch(:excluded))
    @recommendation["timing"] = "before_vote"
    @recommendation["conditions"] = "Only after a public hearing."
    @recommendation["quote"] += " Only after a public hearing."
    @document.update!(extracted_text: @recommendation.fetch("quote"))
    extract_recommendations
    assert_match(/conditions/, recommendation_report.groups.sole.fetch(:rows).sole.fetch(:excluded))
  end

  test "duplicate source copies count once conflicting versions exclude and departments remain distinct" do
    extract_recommendations
    copy = @document.dup
    copy.source_url = "https://example.test/copied-minutes.pdf"
    copy.document_type = "minutes_pdf"
    copy.save!
    @document = copy
    extract_recommendations
    assert_equal 1, recommendation_report.groups.sole.fetch(:compared)
    conflicting = @recommendation.merge("position" => "oppose", "quote" => "Before the decision, City Manager Alex Manager opposed: #{@motion.description}.")
    department = conflicting.merge("author" => "Public Works", "role" => nil, "author_kind" => "department",
      "quote" => "Before the decision, Public Works opposed: #{@motion.description}.")
    @document.update!(extracted_text: [ conflicting, department ].map { |row| row["quote"] }.join("\n"))
    extract_recommendations([ conflicting, department ])
    groups = recommendation_report.groups
    assert_equal 2, groups.size
    assert_equal 0, groups.find { |group| group.dig(:author, "author") == "Alex Manager" }.fetch(:compared)
    works = groups.find { |group| group.dig(:author, "author") == "Public Works" }
    assert_equal 1, works.fetch(:compared)
    assert_equal 0, works.fetch(:supported)
  end

  test "missing recommendations unknown ballots duplicate meeting copies and service dates cannot inflate fractions" do
    extract_recommendations
    unrecorded = @motion.meeting.motions.create!(description: "Purchase a street sweeper", outcome: "passed")
    assert_equal 1, recommendation_report.missing_count
    %w[abstain absent recused].each do |value|
      @motion.votes.find_by!(member: @member).update!(value: value)
      assert_equal 0, recommendation_report.groups.sole.fetch(:compared)
    end
    @motion.votes.find_by!(member: @member).update!(value: "yes", evidence_basis: "attendance_derived")
    assert_equal 0, recommendation_report.groups.sole.fetch(:compared)
    @motion.votes.find_by!(member: @member).update!(evidence_basis: "explicit")
    assert_equal 1, recommendation_report.groups.sole.fetch(:compared)
    duplicate = council_meeting("2025-06-02")
    duplicate.motions.create!(description: unrecorded.description).votes.create!(member: @member, value: "yes")
    assert_equal 0, recommendation_report.groups.sole.fetch(:compared)
    duplicate.destroy!
    assert_equal 1, recommendation_report(term: "all").groups.sole.fetch(:compared)
    @period.update!(ended_on: Date.new(2025, 5, 31), end_source_version: @source, end_page: 5)
    assert_empty recommendation_report(term: "all").groups
  end

  test "named officeholders stay separate and changed evidence disappears on the next request without changing votes" do
    stage = extract_recommendations
    path = recommendation_path
    get path
    assert_select "[data-recommendation-result=supported]", count: 1
    revised = @recommendation.merge("author" => "Morgan Successor", "quote" => @recommendation["quote"].sub("Alex Manager", "Morgan Successor"))
    @document.update!(extracted_text: revised["quote"])
    get member_path(@member)
    assert_select "#staff-recommendations", count: 0
    get path
    assert_response :not_found
    assert_no_difference("Vote.count") { extract_recommendations([ revised ]) }
    get recommendation_path
    assert_select "h2", text: "Morgan Successor"
    assert_select "blockquote", text: revised["quote"]
    assert_equal "Alex Manager", stage.reload.data.fetch("recommendations").sole.fetch("author")
  end

  test "parser rejects unlocated author role proposal missing arrays and oversized recommendation sets" do
    parser = CouncilProfiles::IssueUpdates.new(CouncilProfiles::ExtractIssueUpdates.prepare(@document).context)
    valid = { complete: true, updates: [], actions: [], recommendations: [ @recommendation ] }
    assert_equal 1, parser.parse(valid.to_json).fetch("recommendations").size
    %w[author role proposal].each do |key|
      invalid = valid.deep_dup
      invalid[:recommendations].first[key] = "Unrecorded material"
      assert_raises(CouncilProfiles::IssueUpdates::InvalidResponse) { parser.parse(invalid.to_json) }
    end
    assert_raises(CouncilProfiles::IssueUpdates::InvalidResponse) { parser.parse(valid.except(:recommendations).to_json) }
    assert_raises(CouncilProfiles::IssueUpdates::InvalidResponse) { parser.parse(valid.merge(recommendations: [ @recommendation ] * 41).to_json) }
  end

  test "gated reader and verified Google receive evidence but anonymous and spoofed requests do not" do
    extract_recommendations
    path = recommendation_path
    SiteSetting.instance.update!(access_mode: "gated")
    sign_in_as(User.create!(email_address: "recommendation-reader@example.test", status: "active"))
    get path
    assert_select ".gated-content [data-recommendation-result=supported]", count: 1
    assert_includes response.body, @recommendation["quote"]
    delete public_session_path
    get path
    assert_select "[data-recommendation-result]", count: 0
    assert_not_includes response.body, @recommendation["quote"]
    assert_includes response.headers["Cache-Control"], "no-store"
    get member_path(@member)
    assert_select "#staff-recommendations", count: 0
    get recommendation_path(format: :json)
    assert_response :not_acceptable

    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(Crawlers::IpRanges.new.cache_key(:google), { prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i })
    headers = { "User-Agent" => "Googlebot/2.1 (+http://www.google.com/bot.html)", "REMOTE_ADDR" => "66.249.66.1" }
    get path, headers: headers
    assert_select "[data-recommendation-result=supported]", count: 1
    get path, headers: headers.merge("REMOTE_ADDR" => "198.51.100.42")
    assert_select "[data-recommendation-result]", count: 0
    assert_not_includes response.body, @recommendation["quote"]
  ensure
    Rails.cache = previous_cache if previous_cache
  end
end
