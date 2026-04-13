require "test_helper"
require "ostruct"

class MeetingsHelperTest < ActionView::TestCase
  test "meeting_status_badge returns nil for upcoming meeting with no documents" do
    meeting = OpenStruct.new(document_status: :none, starts_at: 2.days.from_now, meeting_summaries: [])
    assert_nil meeting_status_badge(meeting)
  end

  test "meeting_status_badge returns agenda posted for upcoming meeting with agenda" do
    meeting = OpenStruct.new(document_status: :agenda, starts_at: 2.days.from_now, meeting_summaries: [])
    result = meeting_status_badge(meeting)
    assert_includes result, "Agenda posted"
  end

  test "meeting_status_badge returns documents available for upcoming meeting with packet" do
    meeting = OpenStruct.new(document_status: :packet, starts_at: 2.days.from_now, meeting_summaries: [])
    result = meeting_status_badge(meeting)
    assert_includes result, "Documents available"
  end

  test "meeting_status_badge returns awaiting minutes for past meeting without minutes" do
    meeting = OpenStruct.new(document_status: :none, starts_at: 2.days.ago, meeting_summaries: [])
    result = meeting_status_badge(meeting)
    assert_includes result, "Awaiting minutes"
  end

  test "meeting_status_badge returns awaiting minutes for past meeting with only packet" do
    meeting = OpenStruct.new(document_status: :packet, starts_at: 2.days.ago, meeting_summaries: [])
    result = meeting_status_badge(meeting)
    assert_includes result, "Awaiting minutes"
  end

  test "meeting_status_badge returns minutes available for past meeting with minutes" do
    meeting = OpenStruct.new(document_status: :minutes, starts_at: 2.days.ago, meeting_summaries: [])
    result = meeting_status_badge(meeting)
    assert_includes result, "Minutes available"
  end

  test "meeting_status_badge adds summary badge when summaries exist" do
    summary = OpenStruct.new
    meeting = OpenStruct.new(document_status: :minutes, starts_at: 2.days.ago, meeting_summaries: [ summary ])
    result = meeting_status_badge(meeting)
    assert_includes result, "Summary"
  end

  test "meeting_status_badge treats meeting within buffer as upcoming" do
    meeting = OpenStruct.new(document_status: :agenda, starts_at: 2.hours.ago, meeting_summaries: [])
    result = meeting_status_badge(meeting)
    assert_includes result, "Agenda posted"
  end

  # --- generation_data extraction helpers ---

  setup do
    @generation_data = {
      "headline" => "Council approved $2.5M borrowing 6-3, tabled property assessment policy.",
      "highlights" => [
        { "text" => "Adopted intent-to-reimburse resolution", "citation" => "Page 3", "vote" => "6-3", "impact" => "high" },
        { "text" => "Tabled property assessment ordinance", "citation" => "Page 2", "vote" => nil, "impact" => "high" }
      ],
      "public_input" => [
        { "speaker" => "Jim Smith", "type" => "public_comment", "summary" => "Raised concerns about building condition" },
        { "speaker" => "Councilmember Jones", "type" => "communication", "summary" => "Contacted by resident about parking" }
      ],
      "item_details" => [
        {
          "agenda_item_title" => "Rezoning at 3204 Lincoln Ave",
          "summary" => "Plan Commission recommended approval.",
          "public_hearing" => "Three calls for public input. No one spoke.",
          "decision" => "Passed",
          "vote" => "7-0",
          "citations" => [ "Page 2" ]
        },
        {
          "agenda_item_title" => "Property Assessment Ordinance",
          "summary" => "Council chose to table rather than vote.",
          "public_hearing" => nil,
          "decision" => "Tabled",
          "vote" => nil,
          "citations" => [ "Page 2" ]
        }
      ]
    }
  end

  test "meeting_headline extracts headline" do
    assert_equal "Council approved $2.5M borrowing 6-3, tabled property assessment policy.",
      meeting_headline(@generation_data)
  end

  test "meeting_headline returns nil for missing data" do
    assert_nil meeting_headline(nil)
    assert_nil meeting_headline({})
  end

  test "meeting_highlights extracts highlights array" do
    highlights = meeting_highlights(@generation_data)
    assert_equal 2, highlights.size
    assert_equal "6-3", highlights.first["vote"]
  end

  test "meeting_highlights returns empty array for missing data" do
    assert_equal [], meeting_highlights(nil)
    assert_equal [], meeting_highlights({})
  end

  test "meeting_public_input extracts public input array" do
    inputs = meeting_public_input(@generation_data)
    assert_equal 2, inputs.size
    assert_equal "public_comment", inputs.first["type"]
  end

  test "meeting_public_input returns empty array for missing data" do
    assert_equal [], meeting_public_input(nil)
  end

  test "meeting_item_details extracts item details array" do
    items = meeting_item_details(@generation_data)
    assert_equal 2, items.size
    assert_equal "Passed", items.first["decision"]
    assert_equal "7-0", items.first["vote"]
  end

  test "meeting_item_details returns empty array for missing data" do
    assert_equal [], meeting_item_details(nil)
  end

  test "decision_badge_class returns correct CSS class" do
    assert_equal "decision-badge--passed", decision_badge_class("Passed")
    assert_equal "decision-badge--failed", decision_badge_class("Failed")
    assert_equal "decision-badge--tabled", decision_badge_class("Tabled")
    assert_equal "decision-badge--tabled", decision_badge_class("Referred")
    assert_equal "decision-badge--default", decision_badge_class("Other")
    assert_equal "decision-badge--default", decision_badge_class(nil)
  end

  # --- share_text helper ---

  test "share_text for past meeting with generation_data includes headline and highlights" do
    meeting = OpenStruct.new(
      id: 42,
      body_name: "Common Council Meeting",
      starts_at: 2.days.ago
    )
    summary = OpenStruct.new(generation_data: @generation_data)

    text = share_text(meeting, summary)

    assert_includes text, "Common Council"
    assert_no_match(/Common Council Meeting/, text) # strips " Meeting" suffix
    assert_includes text, meeting.starts_at.strftime("%B %-d, %Y")
    assert_includes text, meeting.starts_at.strftime("%-l:%M %p")
    assert_includes text, @generation_data["headline"]
    assert_includes text, "Key decisions:"
    assert_includes text, "Adopted intent-to-reimburse resolution"
    assert_includes text, "Tabled property assessment ordinance"
    assert_includes text, "https://tworiversmatters.com/meetings/42"
    assert_includes text, "Two Rivers Matters"
  end

  test "share_text for past meeting caps at 5 highlights" do
    many_highlights = 7.times.map { |i| { "text" => "Decision #{i}" } }
    gd = { "headline" => "Big meeting.", "highlights" => many_highlights }
    meeting = OpenStruct.new(id: 1, body_name: "Council Meeting", starts_at: 1.day.ago)
    summary = OpenStruct.new(generation_data: gd)

    text = share_text(meeting, summary)

    assert_equal 5, text.scan(/^ - /).size
  end

  test "share_text for past meeting includes vote when present" do
    meeting = OpenStruct.new(id: 1, body_name: "Council Meeting", starts_at: 1.day.ago)
    summary = OpenStruct.new(generation_data: @generation_data)

    text = share_text(meeting, summary)

    assert_includes text, "6-3"
  end

  test "share_text for upcoming meeting prefers highlights over raw titles" do
    meeting = OpenStruct.new(
      id: 154,
      body_name: "Plan Commission Meeting",
      starts_at: 2.days.from_now
    )
    summary = OpenStruct.new(generation_data: @generation_data)

    text = share_text(meeting, summary)

    assert_includes text, "Plan Commission"
    assert_includes text, "On the agenda:"
    # Uses highlight text (plain language), not raw agenda_item_title
    assert_includes text, "Adopted intent-to-reimburse resolution"
    assert_no_match(/Rezoning at 3204 Lincoln Ave/, text)
  end

  test "share_text for upcoming meeting falls back to item titles when no highlights" do
    gd = { "headline" => "Upcoming meeting.", "item_details" => @generation_data["item_details"] }
    meeting = OpenStruct.new(id: 1, body_name: "Council Meeting", starts_at: 2.days.from_now)
    summary = OpenStruct.new(generation_data: gd)

    text = share_text(meeting, summary)

    assert_includes text, "On the agenda:"
    assert_includes text, "Rezoning at 3204 Lincoln Ave"
  end

  test "share_text falls back to agenda items when no summary" do
    agenda_item = OpenStruct.new(title: "Budget Amendment Discussion")
    meeting = OpenStruct.new(
      id: 10,
      body_name: "Finance Committee Meeting",
      starts_at: 1.day.from_now,
      agenda_items: [ agenda_item ]
    )

    text = share_text(meeting, nil)

    assert_includes text, "Finance Committee"
    assert_includes text, "On the agenda:"
    assert_includes text, "Budget Amendment Discussion"
    assert_includes text, "https://tworiversmatters.com/meetings/10"
  end

  test "share_text agenda fallback filters procedural items" do
    items = [
      OpenStruct.new(title: "CALL TO ORDER"),
      OpenStruct.new(title: "ROLL CALL"),
      OpenStruct.new(title: "Water Rate Increase"),
      OpenStruct.new(title: "ADJOURNMENT")
    ]
    meeting = OpenStruct.new(
      id: 10,
      body_name: "Council Meeting",
      starts_at: 1.day.from_now,
      agenda_items: items
    )

    text = share_text(meeting, nil)

    assert_includes text, "Water Rate Increase"
    assert_no_match(/CALL TO ORDER/, text)
    assert_no_match(/ROLL CALL/, text)
    assert_no_match(/ADJOURNMENT/, text)
  end

  test "share_text minimal fallback when no summary and no agenda items" do
    meeting = OpenStruct.new(
      id: 10,
      body_name: "Council Meeting",
      starts_at: 1.day.from_now
    )

    text = share_text(meeting, nil)

    assert_includes text, "Council"
    assert_includes text, "https://tworiversmatters.com/meetings/10"
    assert_no_match(/On the agenda/, text)
    assert_no_match(/Key decisions/, text)
  end

  # --- OG meta helpers ---

  test "share_og_description extracts headline truncated to 200 chars" do
    long_headline = "A" * 250
    summary = OpenStruct.new(generation_data: { "headline" => long_headline })

    result = share_og_description(summary)

    assert_equal 200, result.length
    assert result.end_with?("...")
  end

  test "share_og_description returns headline when under 200 chars" do
    summary = OpenStruct.new(generation_data: @generation_data)

    result = share_og_description(summary)

    assert_equal @generation_data["headline"], result
  end

  test "share_og_description returns default when no summary" do
    result = share_og_description(nil)

    assert_equal "Meeting details and AI-generated summary.", result
  end

  test "share_og_description returns default when no generation_data" do
    summary = OpenStruct.new(generation_data: nil)

    result = share_og_description(summary)

    assert_equal "Meeting details and AI-generated summary.", result
  end
end
