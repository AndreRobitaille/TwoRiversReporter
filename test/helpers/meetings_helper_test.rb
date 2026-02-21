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
    meeting = OpenStruct.new(document_status: :minutes, starts_at: 2.days.ago, meeting_summaries: [summary])
    result = meeting_status_badge(meeting)
    assert_includes result, "Summary"
  end

  test "meeting_status_badge treats meeting within buffer as upcoming" do
    meeting = OpenStruct.new(document_status: :agenda, starts_at: 2.hours.ago, meeting_summaries: [])
    result = meeting_status_badge(meeting)
    assert_includes result, "Agenda posted"
  end
end
