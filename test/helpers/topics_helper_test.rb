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
end
