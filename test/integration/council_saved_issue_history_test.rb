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
    statement = Struct.new(:data, :related_topics, :campaign_source_version).new({ "kind" => "position" }, [ @topic ],
      Struct.new(:published_on, :election_on).new(Date.new(2024, 4, 1), Date.new(2024, 4, 2)))
    assert_empty Campaigns::IssueEvidenceCandidates.for_member(@member, statements: [ statement ])
    stage = extract_issue_updates
    get member_path(@member)
    assert_select "#issue-updates [data-issue-update]", count: 2
    assert_select "#issue-updates", text: /construction has not begun/, count: 0
    candidates = Campaigns::IssueEvidenceCandidates.for_member(@member, statements: [ statement ])
    assert_equal 2, candidates.size
    assert_equal [ stage.id ], candidates.map { |row| row.fetch(:review).id }.uniq
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
