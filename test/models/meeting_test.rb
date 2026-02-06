require "test_helper"

class MeetingTest < ActiveSupport::TestCase
  test "document_status returns :minutes when minutes_pdf is present" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/1", starts_at: Time.current)
    meeting.meeting_documents.create!(document_type: "minutes_pdf")

    assert_equal :minutes, meeting.document_status
  end

  test "document_status returns :minutes when minutes_pdf AND agenda_pdf are present" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/1b", starts_at: Time.current)
    meeting.meeting_documents.create!(document_type: "minutes_pdf")
    meeting.meeting_documents.create!(document_type: "agenda_pdf")

    assert_equal :minutes, meeting.document_status
  end

  test "document_status returns :agenda when agenda_pdf is present and no minutes" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/2", starts_at: Time.current)
    meeting.meeting_documents.create!(document_type: "agenda_pdf")

    assert_equal :agenda, meeting.document_status
  end

  test "document_status returns :packet when packet_pdf is present and no minutes" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/3", starts_at: Time.current)
    meeting.meeting_documents.create!(document_type: "packet_pdf")

    assert_equal :packet, meeting.document_status
  end

  test "document_status returns :packet when packet_pdf AND agenda_pdf are present" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/3b", starts_at: Time.current)
    meeting.meeting_documents.create!(document_type: "packet_pdf")
    meeting.meeting_documents.create!(document_type: "agenda_pdf")

    assert_equal :packet, meeting.document_status
  end

  test "document_status returns :none when no relevant documents present" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/4", starts_at: Time.current)
    meeting.meeting_documents.create!(document_type: "other_pdf")

    assert_equal :none, meeting.document_status
  end

  test "document_status returns :none when no documents present" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/5", starts_at: Time.current)

    assert_equal :none, meeting.document_status
  end
end
