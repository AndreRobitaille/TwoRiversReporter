require "test_helper"

class TranscriptImportTest < ActiveSupport::TestCase
  setup do
    @meeting = Meeting.create!(detail_page_url: "https://example.com/meetings/1")
  end

  test "validates status" do
    transcript_import = TranscriptImport.new(
      meeting: @meeting,
      youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o",
      status: "mystery"
    )

    assert_not transcript_import.valid?
    assert_includes transcript_import.errors[:status], "is not included in the list"
  end

  test "appends structured step logs" do
    transcript_import = TranscriptImport.create!(
      meeting: @meeting,
      youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o",
      status: "queued"
    )

    freeze_time do
      expected_at = Time.current.iso8601
      transcript_import.append_step_log!(
        step: "download_transcript",
        message: "Downloaded transcript",
        metadata: { meeting_document_id: 123, text_chars: 456 }
      )

      log_entry = transcript_import.reload.step_logs.last
      assert_equal expected_at, log_entry["at"]
    end

    log_entry = transcript_import.reload.step_logs.last
    assert_equal "info", log_entry["level"]
    assert_equal "download_transcript", log_entry["step"]
    assert_equal "Downloaded transcript", log_entry["message"]
    assert_equal 123, log_entry.dig("metadata", "meeting_document_id")
    assert_equal 456, log_entry.dig("metadata", "text_chars")
  end

  test "mark_failed stores troubleshooting details" do
    transcript_import = TranscriptImport.create!(
      meeting: @meeting,
      youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o",
      status: "running",
      started_at: 1.minute.ago
    )

    error = RuntimeError.new("yt-dlp failed")
    error.set_backtrace([ "app/services/documents/transcript_downloader.rb:42:in `download'" ])

    freeze_time do
      expected_finished_at = Time.current
      transcript_import.mark_failed!(error, step: "download_transcript")

      transcript_import.reload
      assert_equal expected_finished_at, transcript_import.finished_at
    end

    transcript_import.reload
    assert_equal "failed", transcript_import.status
    assert_equal "RuntimeError", transcript_import.error_class
    assert_equal "yt-dlp failed", transcript_import.error_message
    assert_includes transcript_import.error_backtrace, "transcript_downloader.rb:42"
    assert_equal "error", transcript_import.step_logs.last["level"]
    assert_equal "download_transcript", transcript_import.step_logs.last["step"]
  end

  test "mark_completed records affected topics and document" do
    transcript_import = TranscriptImport.create!(
      meeting: @meeting,
      youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o",
      status: "running",
      started_at: 1.minute.ago
    )

    document = MeetingDocument.create!(meeting: @meeting)

    freeze_time do
      expected_finished_at = Time.current
      transcript_import.mark_completed!(meeting_document: document, affected_topic_ids: [ 3, 1, 3 ])

      transcript_import.reload
      assert_equal expected_finished_at, transcript_import.finished_at
    end

    transcript_import.reload
    assert_equal "completed", transcript_import.status
    assert_equal document.id, transcript_import.meeting_document_id
    assert_equal [ 1, 3 ], transcript_import.affected_topic_ids
  end

  test "mark_running clears terminal state fields" do
    transcript_import = TranscriptImport.create!(
      meeting: @meeting,
      youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o",
      status: "failed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      error_class: "RuntimeError",
      error_message: "boom",
      error_backtrace: "trace"
    )

    freeze_time do
      expected_started_at = Time.current
      transcript_import.mark_running!

      transcript_import.reload
      assert_equal expected_started_at, transcript_import.started_at
      assert_nil transcript_import.finished_at
      assert_nil transcript_import.error_class
      assert_nil transcript_import.error_message
      assert_nil transcript_import.error_backtrace
    end
  end

  test "failed to running to completed clears terminal state and preserves valid transitions" do
    transcript_import = TranscriptImport.create!(
      meeting: @meeting,
      youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o",
      status: "failed",
      started_at: 3.minutes.ago,
      finished_at: 2.minutes.ago,
      error_class: "RuntimeError",
      error_message: "boom",
      error_backtrace: "trace"
    )

    document = MeetingDocument.create!(meeting: @meeting)

    transcript_import.mark_running!

    freeze_time do
      transcript_import.mark_completed!(meeting_document: document, affected_topic_ids: [ 2, 2, 1 ])
    end

    transcript_import.reload
    assert_equal "completed", transcript_import.status
    assert_nil transcript_import.error_class
    assert_nil transcript_import.error_message
    assert_nil transcript_import.error_backtrace
    assert_equal [ 1, 2 ], transcript_import.affected_topic_ids
  end

  test "validates meeting_document belongs to same meeting" do
    other_meeting = Meeting.create!(detail_page_url: "https://example.com/meetings/2")
    other_document = MeetingDocument.create!(meeting: other_meeting)

    transcript_import = TranscriptImport.new(
      meeting: @meeting,
      meeting_document: other_document,
      youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o",
      status: "queued"
    )

    assert_not transcript_import.valid?
    assert_includes transcript_import.errors[:meeting_document], "must belong to the same meeting"
  end
end
