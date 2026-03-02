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
      "editorial_analysis" => { "process_concerns" => ["No public input.", "Rushed timeline."] }
    })
    assert_equal ["No public input.", "Rushed timeline."], briefing_process_concerns(briefing)
  end

  test "briefing_process_concerns returns empty array when missing" do
    briefing = OpenStruct.new(generation_data: { "editorial_analysis" => {} })
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

  test "briefing_headline_text extracts from generation_data with fallback" do
    briefing = OpenStruct.new(generation_data: { "headline" => "From JSON" }, headline: "From field")
    assert_equal "From JSON", briefing_headline_text(briefing)
  end

  test "briefing_headline_text falls back to headline field" do
    briefing = OpenStruct.new(generation_data: nil, headline: "From field")
    assert_equal "From field", briefing_headline_text(briefing)
  end

  test "format_record_date formats ISO date as month day year" do
    assert_equal "Sep 2, 2025", format_record_date("2025-09-02")
    assert_equal "Nov 15, 2025", format_record_date("2025-11-15")
  end

  test "format_record_date returns original string for unparseable dates" do
    assert_equal "not a date", format_record_date("not a date")
  end
end
