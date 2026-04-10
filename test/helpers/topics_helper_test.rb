require "test_helper"
require "ostruct"

class TopicsHelperTest < ActionView::TestCase
  test "motion_outcome_text returns outcome with vote count" do
    votes = [
      OpenStruct.new(value: "yes"),
      OpenStruct.new(value: "yes"),
      OpenStruct.new(value: "yes"),
      OpenStruct.new(value: "no"),
      OpenStruct.new(value: "no")
    ]
    motion = OpenStruct.new(outcome: "Passed", votes: votes)

    assert_equal "Passed 3-2", motion_outcome_text(motion)
  end

  test "motion_outcome_text returns just outcome when no votes" do
    motion = OpenStruct.new(outcome: "Adopted", votes: [])

    assert_equal "Adopted", motion_outcome_text(motion)
  end

  test "motion_outcome_text handles unanimous votes" do
    votes = [
      OpenStruct.new(value: "yes"),
      OpenStruct.new(value: "yes"),
      OpenStruct.new(value: "yes")
    ]
    motion = OpenStruct.new(outcome: "Approved", votes: votes)

    assert_equal "Approved 3-0", motion_outcome_text(motion)
  end

  test "public_comment_meeting? detects public hearing in title" do
    item = OpenStruct.new(title: "PUBLIC HEARING - Rezoning Request")
    assert public_comment_meeting?(item)
  end

  test "public_comment_meeting? detects public comment in title" do
    item = OpenStruct.new(title: "Public Comment Period")
    assert public_comment_meeting?(item)
  end

  test "public_comment_meeting? returns false for normal items" do
    item = OpenStruct.new(title: "Regular Business Item")
    refute public_comment_meeting?(item)
  end

  test "public_comment_meeting? returns false for nil title" do
    item = OpenStruct.new(title: nil)
    refute public_comment_meeting?(item)
  end

  test "render_topic_summary_content strips section headers and renders list" do
    content = <<~MD
      ## Street Repair

      **Factual Record**
      - City approved $50k funding [Packet Page 5].
      - Work begins in spring.

      **Institutional Framing**
      - Presented as routine maintenance.

      **Civic Sentiment**
      - Residents expressed concern about delays.
    MD

    result = render_topic_summary_content(content)
    assert_includes result, "<li>"
    assert_includes result, "City approved $50k funding [Packet Page 5]."
    assert_includes result, "Residents expressed concern about delays."
    refute_includes result, "Factual Record"
    refute_includes result, "Institutional Framing"
    refute_includes result, "Street Repair"
  end

  test "render_topic_summary_content returns empty string for blank content" do
    assert_equal "", render_topic_summary_content(nil)
    assert_equal "", render_topic_summary_content("")
  end

  test "render_topic_summary_content handles content with only headers" do
    content = "## Topic Name\n\n**Factual Record**\n"
    assert_equal "", render_topic_summary_content(content)
  end

  test "highlight_signal_label returns Delayed for deferral_signal" do
    assert_equal "Delayed", highlight_signal_label("deferral_signal")
  end

  test "highlight_signal_label returns No longer on agenda for disappearance_signal" do
    assert_equal "No longer on agenda", highlight_signal_label("disappearance_signal")
  end

  test "highlight_signal_label returns Moved to new committee for cross_body_progression" do
    assert_equal "Moved to new committee", highlight_signal_label("cross_body_progression")
  end

  test "briefing_what_to_watch extracts from generation_data" do
    briefing = OpenStruct.new(generation_data: {
      "editorial_analysis" => { "what_to_watch" => "Watch for a vote on the budget." }
    })
    assert_equal "Watch for a vote on the budget.", briefing_what_to_watch(briefing)
  end

  test "briefing_what_to_watch returns nil when generation_data is nil" do
    briefing = OpenStruct.new(generation_data: nil)
    assert_nil briefing_what_to_watch(briefing)
  end

  test "briefing_what_to_watch returns nil for nil briefing" do
    assert_nil briefing_what_to_watch(nil)
  end

  test "briefing_current_state extracts from generation_data" do
    briefing = OpenStruct.new(generation_data: {
      "editorial_analysis" => { "current_state" => "The council approved the plan." }
    })
    assert_equal "The council approved the plan.", briefing_current_state(briefing)
  end

  test "briefing_current_state falls back to editorial_content" do
    briefing = OpenStruct.new(generation_data: nil, editorial_content: "Fallback content.")
    assert_equal "Fallback content.", briefing_current_state(briefing)
  end

  test "briefing_process_concerns extracts from generation_data" do
    briefing = OpenStruct.new(generation_data: {
      "editorial_analysis" => { "process_concerns" => [ "No public input.", "Rushed timeline." ] }
    })
    assert_equal [ "No public input.", "Rushed timeline." ], briefing_process_concerns(briefing)
  end

  test "briefing_process_concerns returns empty array when missing" do
    briefing = OpenStruct.new(generation_data: { "editorial_analysis" => {} })
    assert_equal [], briefing_process_concerns(briefing)
  end

  test "briefing_process_concerns handles string format from new schema" do
    briefing = OpenStruct.new(generation_data: {
      "editorial_analysis" => { "process_concerns" => "Topic deferred 3 times without explanation." }
    })
    assert_equal [ "Topic deferred 3 times without explanation." ], briefing_process_concerns(briefing)
  end

  test "briefing_process_concerns handles null from new schema" do
    briefing = OpenStruct.new(generation_data: {
      "editorial_analysis" => { "process_concerns" => nil }
    })
    assert_equal [], briefing_process_concerns(briefing)
  end

  test "briefing_factual_record extracts structured entries from generation_data" do
    briefing = OpenStruct.new(generation_data: {
      "factual_record" => [
        { "date" => "2025-09-02", "event" => "Council approved plan.", "meeting" => "City Council, Sep 2" },
        { "date" => "2025-11-05", "event" => "Item appeared on agenda.", "meeting" => "Public Works, Nov 5" }
      ]
    })
    result = briefing_factual_record(briefing)
    assert_equal 2, result.size
    assert_equal "2025-09-02", result.first["date"]
  end

  test "briefing_factual_record returns empty array when generation_data is nil" do
    briefing = OpenStruct.new(generation_data: nil)
    assert_equal [], briefing_factual_record(briefing)
  end

  test "format_record_date formats ISO date as month day year" do
    assert_equal "Sep 2, 2025", format_record_date("2025-09-02")
    assert_equal "Nov 15, 2025", format_record_date("2025-11-15")
  end

  test "format_record_date returns original string for unparseable dates" do
    assert_equal "not a date", format_record_date("not a date")
  end

  test "enrich_record_entry returns meeting when appearance found" do
    meeting = OpenStruct.new(id: 1, body_name: "City Council")
    appearance = OpenStruct.new(meeting: meeting, agenda_item: nil)
    record_meetings = { "2025-09-02:City Council" => appearance }

    entry = { "date" => "2025-09-02", "event" => "Council approved plan.", "meeting" => "City Council" }
    result = enrich_record_entry(entry, record_meetings)

    assert_equal "Council approved plan.", result[:event]
    assert_equal meeting, result[:meeting]
    assert_equal "City Council", result[:meeting_name]
  end

  test "enrich_record_entry returns nil meeting when no appearance found" do
    record_meetings = {}
    entry = { "date" => "2025-09-02", "event" => "Something happened.", "meeting" => "Unknown Board" }
    result = enrich_record_entry(entry, record_meetings)

    assert_nil result[:meeting]
    assert_equal "Unknown Board", result[:meeting_name]
  end

  test "enrich_record_entry replaces appeared on the agenda with item summary" do
    summary = MeetingSummary.new(
      generation_data: {
        "item_details" => [
          { "agenda_item_title" => "Lead Service Lines", "summary" => "Council approved $2.4M contract with Northern Pipe for replacement." }
        ]
      }
    )
    meeting = OpenStruct.new(id: 1, body_name: "City Council", meeting_summaries: [ summary ])
    agenda_item = OpenStruct.new(title: "Lead Service Lines")
    appearance = OpenStruct.new(meeting: meeting, agenda_item: agenda_item)
    record_meetings = { "2025-09-02:City Council" => appearance }

    entry = { "date" => "2025-09-02", "event" => "Appeared on the agenda.", "meeting" => "City Council" }
    result = enrich_record_entry(entry, record_meetings)

    assert_includes result[:event], "Council approved $2.4M contract"
  end

  test "enrich_record_entry falls back to agenda item title when no summary match" do
    meeting = OpenStruct.new(id: 1, body_name: "City Council", meeting_summaries: [])
    agenda_item = OpenStruct.new(title: "Lead Service Line Replacement Program")
    appearance = OpenStruct.new(meeting: meeting, agenda_item: agenda_item)
    record_meetings = { "2025-09-02:City Council" => appearance }

    entry = { "date" => "2025-09-02", "event" => "Appeared on the agenda.", "meeting" => "City Council" }
    result = enrich_record_entry(entry, record_meetings)

    assert_equal "Lead Service Line Replacement Program", result[:event]
  end

  test "enrich_record_entry keeps original event text when not appeared on the agenda" do
    meeting = OpenStruct.new(id: 1, body_name: "City Council", meeting_summaries: [])
    appearance = OpenStruct.new(meeting: meeting, agenda_item: nil)
    record_meetings = { "2025-09-02:City Council" => appearance }

    entry = { "date" => "2025-09-02", "event" => "Council voted 5-2 to approve.", "meeting" => "City Council" }
    result = enrich_record_entry(entry, record_meetings)

    assert_equal "Council voted 5-2 to approve.", result[:event]
  end
end
