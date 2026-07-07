require "test_helper"

module Documents
  class UploadedTranscriptImporterTest < ActiveSupport::TestCase
    SAMPLE_SRT = <<~SRT
      1
      00:00:01,000 --> 00:00:03,000
      Welcome to the uploaded transcript.

      2
      00:00:04,000 --> 00:00:06,000
      The council discussed utility rates.
    SRT

    def setup
      @meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.zone.local(2026, 3, 15, 18, 0, 0), status: "held", detail_page_url: "http://example.com/meetings/uploaded-transcript-test-#{SecureRandom.hex(4)}")
      @video_url = "https://www.youtube.com/watch?v=abc123"
    end

    test "creates transcript document from uploaded srt attachment" do
      transcript_import = build_transcript_import_with_srt(SAMPLE_SRT, filename: "manual.srt")

      result = UploadedTranscriptImporter.new(
        meeting: @meeting,
        youtube_url: @video_url,
        srt_file: transcript_import.srt_file
      ).import

      assert_predicate result, :created?
      assert_equal "uploaded_srt", result.source

      document = result.meeting_document
      assert_equal @meeting, document.meeting
      assert_equal "transcript", document.document_type
      assert_equal @video_url, document.source_url
      assert_equal "uploaded_transcript", document.text_quality
      assert_includes document.extracted_text, "Welcome to the uploaded transcript."
      assert_includes document.extracted_text, "The council discussed utility rates."
      assert_not_includes document.extracted_text, "00:00:01,000"
      assert_equal document.extracted_text.length, document.text_chars
      assert document.file.attached?
      assert_equal "manual.srt", document.file.filename.to_s
    end

    test "replaces existing transcript document" do
      stale = @meeting.meeting_documents.create!(document_type: "transcript", source_url: @video_url, text_quality: "auto_transcribed", extracted_text: "stale", text_chars: 5)
      stale.file.attach(io: StringIO.new("stale"), filename: "stale.srt", content_type: "text/srt")
      transcript_import = build_transcript_import_with_srt(SAMPLE_SRT)

      result = UploadedTranscriptImporter.new(
        meeting: @meeting,
        youtube_url: @video_url,
        srt_file: transcript_import.srt_file
      ).import

      assert_predicate result, :created?
      assert_not MeetingDocument.exists?(stale.id)
      assert_equal 1, @meeting.meeting_documents.where(document_type: "transcript").count
    end

    test "raises import error when uploaded srt has no transcript text" do
      transcript_import = build_transcript_import_with_srt("1\n00:00:01,000 --> 00:00:03,000\n")

      error = assert_raises(UploadedTranscriptImporter::ImportError) do
        UploadedTranscriptImporter.new(
          meeting: @meeting,
          youtube_url: @video_url,
          srt_file: transcript_import.srt_file
        ).import
      end

      assert_match(/did not contain transcript text/i, error.message)
      assert_equal 0, @meeting.meeting_documents.where(document_type: "transcript").count
    end

    test "removes created record if attaching stored transcript fails" do
      transcript_import = build_transcript_import_with_srt(SAMPLE_SRT)
      importer = UploadedTranscriptImporter.new(
        meeting: @meeting,
        youtube_url: @video_url,
        srt_file: transcript_import.srt_file
      )

      importer.stub :attach_transcript_file, ->(*) { raise StandardError, "attach failed" } do
        assert_raises(StandardError) { importer.import }
      end

      assert_equal 0, @meeting.meeting_documents.where(document_type: "transcript").count
    end

    private

    def build_transcript_import_with_srt(content, filename: "uploaded.srt")
      TranscriptImport.create!(meeting: @meeting, youtube_url: @video_url, status: "queued").tap do |transcript_import|
        transcript_import.srt_file.attach(io: StringIO.new(content), filename: filename, content_type: "text/srt")
      end
    end
  end
end
