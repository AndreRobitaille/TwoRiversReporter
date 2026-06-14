require "test_helper"

class GeneratedImages::MeetingEligibilityTest < ActiveSupport::TestCase
  test "eligible with substantive highlight" do
    meeting = Meeting.create!(body_name: "Council", starts_at: Time.current, detail_page_url: "http://example.com/meeting")
    summary = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "minutes_recap",
      content: "",
      generation_data: {
        "headline" => "Council weighs sidewalk assessments",
        "highlights" => [ { "text" => "Council approved a sidewalk pilot that may bill nearby property owners.", "vote" => "7-0" } ],
        "item_details" => [ { "agenda_item_title" => "Sidewalk replacement program", "summary" => "Repair and billing policy" } ]
      }
    )

    result = GeneratedImages::MeetingEligibility.new(summary.meeting, summary: summary).call

    assert result.eligible?
    assert_equal "Council approved a sidewalk pilot that may bill nearby property owners.", result.primary_text
    assert_not result.composite?
  end

  test "not eligible with only procedural placeholder content" do
    meeting = Meeting.create!(body_name: "Council", starts_at: Time.current, detail_page_url: "http://example.com/meeting-2")
    summary = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "agenda_preview",
      content: "",
      generation_data: {
        "headline" => "The board will meet for routine reports.",
        "highlights" => [ { "text" => "The agenda includes call to order, roll call, approval of minutes, and reports." } ],
        "item_details" => [ { "agenda_item_title" => "Reports and updates" } ]
      }
    )

    result = GeneratedImages::MeetingEligibility.new(summary.meeting, summary: summary).call

    assert_not result.eligible?
    assert_equal "no substantive visual hook", result.reason
  end

  test "composite when three substantive candidates exist" do
    meeting = Meeting.create!(body_name: "Council", starts_at: Time.current, detail_page_url: "http://example.com/meeting-3")
    summary = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "minutes_recap",
      content: "",
      generation_data: {
        "headline" => "Council approves borrowing for street and water work.",
        "highlights" => [
          { "text" => "Council approved the borrowing package for street reconstruction." },
          { "text" => "Members also approved water main repairs and utility rate changes." }
        ],
        "item_details" => [
          { "agenda_item_title" => "Street reconstruction", "summary" => "Street funding and construction details." }
        ]
      }
    )

    result = GeneratedImages::MeetingEligibility.new(summary.meeting, summary: summary).call

    assert result.eligible?
    assert result.composite?
  end

  test "missing summary is not eligible" do
    meeting = Meeting.create!(body_name: "Council", starts_at: Time.current, detail_page_url: "http://example.com/meeting-4")

    result = GeneratedImages::MeetingEligibility.new(meeting).call

    assert_not result.eligible?
    assert_equal "missing summary", result.reason
  end

  test "preferred summary picks newest usable summary among same type" do
    meeting = Meeting.create!(body_name: "Council", starts_at: Time.current, detail_page_url: "http://example.com/meeting-6")

    MeetingSummary.create!(
      meeting: meeting,
      summary_type: "packet_analysis",
      content: "Older content",
      generation_data: { "headline" => "Older packet analysis headline about street repair funding and utility changes.", "highlights" => [ { "text" => "Older approved street repair plan." } ] },
      updated_at: 2.days.ago
    )
    MeetingSummary.create!(
      meeting: meeting,
      summary_type: "packet_analysis",
      content: "Newer content",
      generation_data: { "headline" => "Newer packet analysis headline about street repair funding and utility changes.", "highlights" => [ { "text" => "Newer approved street repair plan." } ] },
      updated_at: 1.day.ago
    )

    result = GeneratedImages::MeetingEligibility.new(meeting).call

    assert result.eligible?
    assert_equal "Newer packet analysis headline about street repair funding and utility changes.", result.primary_text
  end

  test "preferred summary falls back from blank higher tier to usable lower tier" do
    meeting = Meeting.create!(body_name: "Council", starts_at: Time.current, detail_page_url: "http://example.com/meeting-7")

    MeetingSummary.create!(
      meeting: meeting,
      summary_type: "minutes_recap",
      content: "",
      generation_data: {},
      updated_at: 1.hour.ago
    )
    usable = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "packet_analysis",
      content: "",
      generation_data: { "headline" => "Council approved street repairs and utility billing changes for nearby residents.", "highlights" => [ { "text" => "Council approved street repair funding." } ] },
      updated_at: 2.hours.ago
    )

    result = GeneratedImages::MeetingEligibility.new(meeting).call

    assert result.eligible?
    assert_equal usable.generation_data["headline"], result.primary_text
  end

  test "legacy content only summary can be eligible" do
    meeting = Meeting.create!(body_name: "Council", starts_at: Time.current, detail_page_url: "http://example.com/meeting-8")
    MeetingSummary.create!(
      meeting: meeting,
      summary_type: "agenda_preview",
      content: "Council approved a new street reconstruction contract that changes resident assessments.",
      generation_data: {},
      updated_at: 1.hour.ago
    )

    result = GeneratedImages::MeetingEligibility.new(meeting).call

    assert result.eligible?
    assert_match(/street reconstruction contract/i, result.primary_text)
  end

  test "rejects update-only utility discussion" do
    meeting = Meeting.create!(body_name: "Council", starts_at: Time.current, detail_page_url: "http://example.com/meeting-5")
    summary = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "agenda_preview",
      content: "",
      generation_data: {
        "headline" => "Utility updates were discussed at length for the sewer program.",
        "highlights" => [ { "text" => "Utility updates were discussed at length for the sewer program." } ],
        "item_details" => [ { "agenda_item_title" => "Sewer program updates", "summary" => "Staff provided updates." } ]
      }
    )

    result = GeneratedImages::MeetingEligibility.new(summary.meeting, summary: summary).call

    assert_not result.eligible?
    assert_equal "no substantive visual hook", result.reason
  end
end
