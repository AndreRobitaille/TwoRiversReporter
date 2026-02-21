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
end
