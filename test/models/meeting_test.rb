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

  test "document_status returns :transcript when transcript exists but no minutes or packet" do
    meeting = Meeting.create!(
      detail_page_url: "http://example.com/transcript-1",
      starts_at: Time.current
    )
    meeting.meeting_documents.create!(
      document_type: "transcript",
      source_url: "https://www.youtube.com/watch?v=test123"
    )
    assert_equal :transcript, meeting.document_status
  end

  test "document_status returns :minutes even when transcript exists" do
    meeting = Meeting.create!(
      detail_page_url: "http://example.com/transcript-2",
      starts_at: Time.current
    )
    meeting.meeting_documents.create!(document_type: "minutes_pdf")
    meeting.meeting_documents.create!(
      document_type: "transcript",
      source_url: "https://www.youtube.com/watch?v=test123"
    )
    assert_equal :minutes, meeting.document_status
  end

  test "document_status returns :transcript above :agenda" do
    meeting = Meeting.create!(
      detail_page_url: "http://example.com/transcript-3",
      starts_at: Time.current
    )
    meeting.meeting_documents.create!(document_type: "agenda_pdf")
    meeting.meeting_documents.create!(
      document_type: "transcript",
      source_url: "https://www.youtube.com/watch?v=test123"
    )
    assert_equal :transcript, meeting.document_status
  end

  test "processing state helpers read and write meeting parsed marker" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/processing-1", starts_at: Time.current)

    assert_nil meeting.meeting_page_parsed_at
    assert_equal({}, meeting.processing_state)

    meeting.mark_processing!(:meeting_page_parsed_at)
    assert meeting.meeting_page_parsed?
    assert_not_nil meeting.meeting_page_parsed_at
    assert_equal true, meeting.processing_state["meeting_page_parsed_at"]

    meeting.clear_processing!(:meeting_page_parsed_at)
    assert_not meeting.meeting_page_parsed?
    assert_nil meeting.meeting_page_parsed_at
    assert_equal false, meeting.processing_state["meeting_page_parsed_at"]
  end

  test "processing state helpers support generic markers" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/processing-2", starts_at: Time.current)

    meeting.mark_processing!(:agenda_parsed)
    assert_equal true, meeting.processing_state["agenda_parsed"]

    meeting.clear_processing!(:agenda_parsed)
    assert_equal false, meeting.processing_state["agenda_parsed"]
  end

  test "processing marker helpers expose explicit generic API" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/processing-3", starts_at: Time.current)

    meeting.set_processing_marker!(:agenda_parsed)
    assert meeting.processing_marker_set?(:agenda_parsed)

    meeting.clear_processing_marker!(:agenda_parsed)
    assert_not meeting.processing_marker_set?(:agenda_parsed)
  end
end
