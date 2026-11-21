require "test_helper"
require "active_support/testing/constant_stubbing"
require_relative "../support/campaign_issue_evidence_scenario"

class CampaignPlatformTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::ConstantStubbing
  include CampaignIssueEvidenceScenario

  test "new source comparisons consolidate repeats while the archive retains every accepted statement" do
    setup_member_campaign
    data = campaign_response_data
    jordan = data.fetch("participants").first
    first = jordan.fetch("answers").first
    first.fetch("statements").first["comparison_heading"] = "Repair neighborhood water lines"
    second = jordan.fetch("answers").second.fetch("statements").first
    second["comparison_heading"] = nil
    analyze_member_campaign(content: data.to_json)
    first_source = @source
    @source = CampaignSource.create!(campaign_article_attributes.merge(source_url: "https://example.test/separate-interview"))
    analyze_member_campaign(content: data.to_json)

    get member_path(@jordan)
    assert_select "[data-campaign-proposal]", count: 1 do
      assert_select "summary.member-campaign-summary", text: /Repair neighborhood water lines.*Priority/
      assert_select ".member-campaign-empty", count: 1
      assert_select "a[href=?]", first_source.source_url, count: 1
      assert_select "a[href=?]", @source.source_url, count: 1
    end
    assert_select "details.member-campaign-evidence .member-campaign-card", count: 4
    assert_select "details.member-campaign-evidence", text: /Do not delay urgent repairs/
    assert_select "[data-campaign-proposal]", text: /Start with the oldest pipes/, count: 0
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    get member_path(@jordan)
    assert_not_includes response.body, "Repair neighborhood water lines"
  end

  test "a reviewed comparison uses the current personal action even without topic overlap and loses it when its source changes" do
    setup_issue_matching
    @specific.campaign_statement_topics.delete_all
    edition = { "election" => "2024-04-02", "sources" => { "forum" => @source.source_url },
      "members" => { @jordan.name => {
        "digests" => { "forum" => ResidentContent::CampaignPlatform.source_digest([ @specific ]) },
        "items" => [ { "heading" => "Require owners to live at their rentals", "kind" => "Proposal",
          "description" => @specific.data.fetch("summary"), "refs" => [ "forum.#{@specific.sequence}" ],
          "reviewed_action" => { "minutes_url" => @document.source_url, "quote" => @advocacy_quote, "reason" => "The request addressed owner occupancy." } } ] } } }
    stub_const(ResidentContent::CampaignPlatform, :EDITION, edition) do
      evidence = Campaigns::IssueEvidenceCandidates.for_member(@jordan).find { |row| row.dig(:evidence, "quote") == @advocacy_quote }
      input = Campaigns::IssueEvidenceInput.new(evidence.fetch(:review), [ evidence ])
      assert_empty input.pairs_for_review([])
      get member_path(@jordan)
      assert_select "[data-campaign-proposal] [data-campaign-issue-evidence=action]", text: /request did not advance/, count: 1
      assert_select "[data-campaign-proposal] blockquote", text: @advocacy_quote
      @document.update!(extracted_text: "Corrected minutes omit this attributed request.")
      get member_path(@jordan)
      assert_select "[data-campaign-proposal]", count: 1
      assert_select "[data-campaign-proposal] [data-campaign-issue-evidence]", count: 0
      @source.update!(body: @source.body + "\nCorrected campaign source.")
      get member_path(@jordan)
      assert_select "[data-campaign-proposal]", count: 0
    end
  end

  test "a reviewed record corrects a broad comparison while another decision on the same project stays eligible" do
    setup_campaign_actions
    meeting = @vote.motion.meeting
    @vote.motion.agenda_item.update!(title: "25-111 First rental decision")
    next_item = meeting.agenda_items.create!(title: "25-112 Blackstone Property", number: "2")
    @fee.update!(agenda_item: next_item)
    review_campaign_actions
    get member_path(@jordan)
    assert_select "[data-campaign-action=?]", @vote.id

    sources = { "reviewed" => { "label" => "Council minutes", "url" => @document.source_url + "#page=2",
      "passages" => [ @quote ], "docket" => "25-111" },
      "prior" => { "label" => "Earlier staff report", "url" => "https://example.test/earlier-report.pdf", "passages" => [ "Opening a new property." ] } }
    position = { "heading" => "Open a new rental property", "description" => "Help new operators open in town.",
      "kind" => "Position", "refs" => [ "forum.#{@specific.sequence}" ], "compare" => [], "search_terms" => [ "Blackstone Property" ],
      "unrelated_records" => [ "reviewed" ], "reports" => [ { "text" => "Staff reported the application.", "sources" => [ "prior" ] } ] }
    edition = { "election" => "2024-04-02", "sources" => { "forum" => @source.source_url }, "council_sources" => sources,
      "members" => { @jordan.name => { "digests" => { "forum" => ResidentContent::CampaignPlatform.source_digest([ @specific ]) }, "items" => [ position ] } } }
    stub_const(ResidentContent::CampaignPlatform, :EDITION, edition) do
      rows = Campaigns::ActionCandidates.for_member(@jordan).select { |r| r[:statement] == @specific }
      assert_equal [ @fee.id ], rows.map { |r| r.fetch(:vote).motion_id }
      assert rows.first.fetch(:focus).present?
      assert Campaigns::ActionCandidates.for_member(@taylor).any? { |r| r.fetch(:vote).motion == @vote.motion }
      get member_path(@jordan)
      assert_select "[data-campaign-proposal]" do
        assert_select "[data-campaign-action=?]", @vote.id, count: 0
        assert_select "[data-campaign-report] a[href=?]", sources["prior"]["url"]
        assert_select ".member-campaign-empty", count: 0
      end
      @document.update!(extracted_text: "New minutes correct the earlier evidence.")
      assert Campaigns::ActionCandidates.for_member(@jordan).any? { |r| r[:statement] == @specific && r[:vote].id == @vote.id }
      meeting.meeting_documents.create!(document_type: "packet_pdf", source_url: sources["prior"]["url"], extracted_text: "Corrected staff report.")
      get member_path(@jordan)
      assert_select "[data-campaign-report]", count: 0
      assert_select "[data-campaign-proposal] .member-campaign-empty"
    end
  end

  test "two alternatives in one campaign answer get separate decisions and appear under their own headings" do
    setup_campaign_actions
    question = "What would you change about short-term rentals?"
    quote = "Consider a lottery or require owners to live in their rentals for part of each year."
    passage = "Jordan Example: #{quote}"
    @source = CampaignSource.create!(campaign_article_attributes.merge(body: [ question, passage ].join("\n"),
      source_url: "https://example.test/rental-options", published_on: "2024-03-12", election_on: "2024-04-02"))
    analyze_member_campaign(content: { participants: [ { name: @jordan.name, name_quote: passage, answers: [
      { question: question, passage: passage, statements: [ { kind: "position", summary: quote, supporting_quote: quote,
        conditions: nil, timeframe: nil } ] }
    ] } ], coverage_gaps: [] }.to_json)
    row = @source.current_version.extraction.campaign_statements.sole
    topics = Campaigns::MatchTopics.prepare(@source.current_version)
    topic_result = { matches: [ { sequence: row.sequence, status: "matched", topic_ids: [ @water.id ], reason: "Rental policies." } ] }
    with_campaign_transport(content: topic_result.to_json) do
      MatchCampaignTopicsJob.perform_now(@source.id, budget_run_id: campaign_budget(stage: topics).id)
    end
    older = Campaigns::MatchActions.prepare(@vote.motion.meeting).sole
    original = older.context.fetch("pairs").find { |pair| pair["statement_id"] == row.id && pair["motion_id"] == @vote.motion_id }
    old_response = action_response(older)
    old_response.fetch("matches").find { |match| match["key"] == original.fetch("key") }["reason"] = "The motion did not propose a lottery."
    with_campaign_transport(content: old_response.to_json) do
      MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id, budget_run_id: campaign_budget(stage: older).id)
    end
    headings = [ "Consider a lottery for short-term rentals", "Consider an owner-residency rule for short-term rentals" ]
    edition = { "election" => "2024-04-02", "sources" => { "forum" => @source.source_url }, "members" => { @jordan.name => {
      "digests" => { "forum" => ResidentContent::CampaignPlatform.source_digest([ row ]) }, "items" => headings.zip([ "lottery", "owner residency" ]).map { |heading, term|
        { "heading" => heading, "description" => heading, "kind" => "Position", "refs" => [ "forum.0" ], "compare" => [], "prior_review_terms" => [ term ] }
      } } } }
    stub_const(ResidentContent::CampaignPlatform, :EDITION, edition) do
      stage = Campaigns::MatchActions.prepare(@vote.motion.meeting).reject { |review| review.status == "completed" }.sole
      pairs = stage.context.fetch("pairs")
      assert_equal [ headings.last ], pairs.select { |pair| pair["statement_id"] == row.id && pair["motion_id"] == @vote.motion_id }
        .map { |pair| pair.fetch("focus").fetch("heading") }
      assert_equal headings.sort, pairs.select { |pair| pair["statement_id"] == row.id && pair["motion_id"] == @fee.id }
        .map { |pair| pair.fetch("focus").fetch("heading") }.sort
      matches = pairs.map do |pair|
        direct = pair.dig("focus", "heading") == headings.last && pair["motion_id"] == @vote.motion_id
        { key: pair.fetch("key"), status: direct ? "direct" : "not_direct", minutes_quote: direct ? @quote : nil,
          reason: direct ? "The motion proposed an owner residency rule." : "This decision concerned something else." }
      end
      with_campaign_transport(content: { matches: matches }.to_json) do
        MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id, budget_run_id: campaign_budget(stage: stage).id)
      end
      get member_path(@jordan)
      assert_select "[data-campaign-proposal]", count: 2 do |items|
        lottery, residency = headings.map { |heading| items.find { |item| item.at_css("summary").text.include?(heading) } }
        assert_select lottery, "[data-campaign-action]", count: 0
        assert_select residency, "[data-campaign-action=?]", @vote.id, count: 1
        assert_select residency, "blockquote", text: @quote
      end
    end
  end

  test "jobs recover a missing topic link and compare a repeated position once per decision" do
    setup_campaign_activity
    @water.update!(description: "Replacement of aging pipes below residential streets.")
    statements = [ "Start with the oldest pipes and seek grants.", "Seek grants for the oldest pipes." ].map.with_index do |summary, index|
      @source = CampaignSource.create!(campaign_article_attributes.merge(source_url: "https://example.test/pipes-#{index}",
        body: "Interview #{index + 1}\n#{campaign_article_attributes.fetch(:body)}",
        published_on: "2024-03-27", election_on: "2024-04-02"))
      response = campaign_response_data
      answers = response.fetch("participants").first.fetch("answers")
      answers.first.fetch("statements").first["comparison_heading"] = nil
      answers.second.fetch("statements").first.merge!("summary" => summary, "comparison_heading" => "Start with the oldest pipes")
      analyze_member_campaign(content: response.to_json)
      row = CampaignStatement.current_for(@jordan).find { |s| s.campaign_source_version == @source.current_version && s.data["comparison_heading"] }
      assert_empty row.related_topics
      assert_enqueued_with(job: MatchCampaignActionsJob) { MatchCampaignTopicsJob.perform_now(@source.id) }
      row
    end
    vote = activity_vote(date: Date.new(2025, 6, 2), description: "Fund the Lincoln Avenue water main", agenda_title: "Lincoln Avenue reconstruction")
    meeting = vote.motion.meeting
    other = meeting.motions.create!(description: "Paint a crosswalk at the same intersection", agenda_item: vote.motion.agenda_item, outcome: "passed")
    other.votes.create!(member: @jordan, value: "yes")
    quote = "The council approved funding to replace the aging water main on Lincoln Avenue."
    meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/lincoln.pdf", extracted_text: quote)
    preview = -> { Campaigns::ComparisonPreview.call(members: [ @jordan ], from: meeting.starts_at.to_date, through: meeting.starts_at.to_date) }
    assert_no_difference [ "CampaignActionReview.count", "CouncilAiReservation.count", "MinutesExtraction.count" ] do
      assert_operator preview.call.fetch(:new_pairs), :>=, 2
    end
    stage = Campaigns::MatchActions.prepare(meeting).sole
    prepared = preview.call
    assert_equal 0, prepared.fetch(:new_pairs)
    assert_operator prepared.fetch(:previously_prepared_pairs), :>=, 2
    pairs = stage.context.fetch("pairs")
    position_pairs = pairs.select { |pair| statements.map(&:id).include?(pair.fetch("statement_id")) }
    assert_equal [ vote.motion_id, other.id ].sort, position_pairs.map { |pair| pair.fetch("motion_id") }.sort
    archived_ids = statements.map { |s| s.campaign_extraction.campaign_statements.find_by!(member: @jordan, sequence: 0).id }
    assert_empty archived_ids & pairs.pluck("statement_id")
    result = pairs.map do |pair|
      direct = position_pairs.include?(pair) && pair.fetch("motion_id") == vote.motion_id
      { key: pair.fetch("key"), status: direct ? "direct" : "not_direct", reason: direct ? "This funded replacement of an aging main." : "A different decision.",
        minutes_quote: direct ? quote : nil }
    end
    @calls.clear
    with_campaign_transport(content: { matches: result }.to_json) do
      MatchCampaignActionsJob.perform_now(meeting.id, budget_run_id: campaign_budget(stage: stage).id)
    end
    assert_equal 1, @calls.size
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Existing meeting analysis and comparisons must be reused" }) do
      assert_no_difference [ "CampaignActionRequest.count", "MinutesExtraction.count", "MeetingSummary.count", "Vote.count" ] do
        MatchCampaignActionsJob.perform_now(meeting.id)
        replay = preview.call
        assert_equal prepared.fetch(:previously_prepared_pairs), replay.fetch(:saved_pairs)
        assert_equal 0, replay.fetch(:new_pairs)
        assert_empty replay.fetch(:batches)
        get member_path(@jordan)
        assert_select "[data-campaign-proposal]", count: 1 do
          assert_select "[data-campaign-action=?]", vote.id
          assert_select "blockquote", text: quote
          assert_select "[data-campaign-action=?]", other.votes.sole.id, count: 0
        end
      end
    end
  end
end
