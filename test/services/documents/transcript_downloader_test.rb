require "test_helper"
require "ostruct"

module Documents
  class TranscriptDownloaderTest < ActiveSupport::TestCase
    SAMPLE_SRT = <<~SRT
      1
      00:00:01,000 --> 00:00:03,000
      Welcome to the city council meeting.

      2
      00:00:04,000 --> 00:00:06,500
      Tonight we will discuss the budget proposal.
    SRT

    def setup
      @meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.zone.local(2026, 3, 15, 18, 0, 0), status: "held", detail_page_url: "http://example.com/meetings/transcript-test-#{SecureRandom.hex(4)}")
      @video_url = "https://www.youtube.com/watch?v=abc123"
    end

    def stub_tmpdir_with_srt(srt_content)
      Dir.mktmpdir("test-transcript") do |tmpdir|
        File.write(File.join(tmpdir, "video.en.srt"), srt_content)
        original = Dir.method(:mktmpdir)
        Dir.define_singleton_method(:mktmpdir) { |*args, &block| args.first == "transcript" ? block.call(tmpdir) : original.call(*args, &block) }
        yield
      ensure
        Dir.define_singleton_method(:mktmpdir, original)
      end
    end

    test "creates transcript document with attached SRT" do
      capture_args = nil
      stub_tmpdir_with_srt(SAMPLE_SRT) do
        Open3.stub :capture3, ->(*args) { capture_args = args; [ "", "", OpenStruct.new(success?: true) ] } do
          result = TranscriptDownloader.new(meeting: @meeting, video_url: @video_url).download_and_store
          assert_predicate result, :created?
        end
      end

      doc = @meeting.meeting_documents.find_by!(document_type: "transcript")
      assert doc.file.attached?
      assert_includes doc.extracted_text, "Welcome to the city council meeting."
      assert_includes capture_args, "--no-update"
      assert_includes capture_args, "--js-runtimes"
      assert_includes capture_args, "node"
      assert_includes capture_args, "--write-sub"
      assert_equal "manual_caption", doc.text_quality
    end

    test "falls back to auto captions and marks transcript auto_transcribed" do
      Dir.mktmpdir("test-transcript") do |tmpdir|
        original = Dir.method(:mktmpdir)
        Dir.define_singleton_method(:mktmpdir) { |*args, &block| args.first == "transcript" ? block.call(tmpdir) : original.call(*args, &block) }

        begin
          attempts = []
          Open3.stub :capture3, ->(*args) {
            attempts << args
            if args.include?("--write-sub")
              [ "", "", OpenStruct.new(success?: true) ]
            else
              File.write(File.join(tmpdir, "video.en.srt"), SAMPLE_SRT)
              [ "", "", OpenStruct.new(success?: true) ]
            end
          } do
            result = TranscriptDownloader.new(meeting: @meeting, video_url: @video_url).download_and_store
            assert_predicate result, :created?
          end

          doc = @meeting.meeting_documents.find_by!(document_type: "transcript")
          assert_equal "auto_transcribed", doc.text_quality
          assert attempts.all? { |args| args.include?("--no-update") }
          assert attempts.all? { |args| args.include?("--js-runtimes") && args.include?("node") }
          assert attempts.any? { |args| args.include?("--write-sub") }
          assert attempts.any? { |args| args.include?("--write-auto-sub") }
        ensure
          Dir.define_singleton_method(:mktmpdir, original)
        end
      end
    end

    test "reuses complete transcript document" do
      doc = MeetingDocument.create!(meeting: @meeting, document_type: "transcript", source_url: @video_url, text_quality: "auto_transcribed", extracted_text: "existing transcript")
      doc.file.attach(io: StringIO.new("srt"), filename: "existing.srt", content_type: "text/srt")

      Open3.stub :capture3, ->(*) { flunk "should not shell out" } do
        result = TranscriptDownloader.new(meeting: @meeting, video_url: @video_url).download_and_store
        assert_predicate result, :reused?
        assert_equal doc, result.meeting_document
      end
    end

    test "rejects invalid URL" do
      Open3.stub :capture3, ->(*) { flunk "should not shell out" } do
        assert_raises(TranscriptDownloader::InvalidUrlError) do
          TranscriptDownloader.new(meeting: @meeting, video_url: "https://evil.com/watch?v=abc").download_and_store
        end
      end
    end

    test "precheck invalid URL does not shell out" do
      Open3.stub :capture3, ->(*) { flunk "should not shell out" } do
        result = TranscriptDownloader.precheck("https://evil.com/watch?v=abc")
        assert_equal :invalid_url, result.status
      end
    end

    test "precheck captions available when english data is non-empty" do
      stdout = { "subtitles" => { "en" => [ { "ext" => "vtt" } ] }, "automatic_captions" => {} }.to_json
      Open3.stub :capture3, [ stdout, "", OpenStruct.new(success?: true) ] do
        result = TranscriptDownloader.precheck(@video_url)
        assert_equal :captions_available, result.status
      end
    end

    test "precheck captions missing when english data is empty" do
      stdout = { "subtitles" => { "en" => [] }, "automatic_captions" => { "en" => [] } }.to_json
      Open3.stub :capture3, [ stdout, "", OpenStruct.new(success?: true) ] do
        result = TranscriptDownloader.precheck(@video_url)
        assert_equal :captions_missing, result.status
        assert_equal "No English captions were found", result.message
      end
    end

    test "precheck captions missing when automatic captions english data is empty" do
      stdout = { "subtitles" => { "en" => [] }, "automatic_captions" => { "en" => [] } }.to_json
      Open3.stub :capture3, [ stdout, "", OpenStruct.new(success?: true) ] do
        result = TranscriptDownloader.precheck(@video_url)
        assert_equal :captions_missing, result.status
        assert_equal "No English captions were found", result.message
      end
    end

    test "precheck verification unavailable on yt-dlp failure" do
      Open3.stub :capture3, [ "", "ERROR: blocked", OpenStruct.new(success?: false) ] do
        result = TranscriptDownloader.precheck(@video_url)
        assert_equal :verification_unavailable, result.status
      end
    end

    test "precheck verification unavailable on missing yt-dlp binary" do
      Open3.stub :capture3, ->(*) { raise Errno::ENOENT, "No such file or directory - yt-dlp" } do
        result = TranscriptDownloader.precheck(@video_url)
        assert_equal :verification_unavailable, result.status
        assert_match(/yt-dlp could not be executed/i, result.message)
      end
    end

    test "download_and_store wraps missing yt-dlp binary as DownloadError" do
      Open3.stub :capture3, ->(*) { raise Errno::ENOENT, "No such file or directory - yt-dlp" } do
        assert_raises(TranscriptDownloader::DownloadError) do
          TranscriptDownloader.new(meeting: @meeting, video_url: @video_url).download_and_store
        end
      end
    end

    test "precheck handles JSON parse errors" do
      Open3.stub :capture3, [ "not json", "", OpenStruct.new(success?: true) ] do
        result = TranscriptDownloader.precheck(@video_url)
        assert_equal :verification_unavailable, result.status
        assert_match(/unreadable metadata/i, result.message)
      end
    end

    test "destroyes stale transcript without file and recreates it" do
      stale = MeetingDocument.create!(meeting: @meeting, document_type: "transcript", source_url: @video_url, text_quality: "auto_transcribed", extracted_text: "stale")

      stub_tmpdir_with_srt(SAMPLE_SRT) do
        Open3.stub :capture3, [ "", "", OpenStruct.new(success?: true) ] do
          result = TranscriptDownloader.new(meeting: @meeting, video_url: @video_url).download_and_store
          assert_predicate result, :created?
        end
      end

      assert_not MeetingDocument.exists?(stale.id)
      assert_equal 1, @meeting.meeting_documents.where(document_type: "transcript").count
    end

    test "removes created record if attach fails" do
      stub_tmpdir_with_srt(SAMPLE_SRT) do
        Open3.stub :capture3, [ "", "", OpenStruct.new(success?: true) ] do
          downloader = TranscriptDownloader.new(meeting: @meeting, video_url: @video_url)
          downloader.stub :attach_transcript_file, ->(*) { raise StandardError, "attach failed" } do
            assert_raises(StandardError) do
              downloader.download_and_store
            end
          end
        end
      end

      assert_equal 0, @meeting.meeting_documents.where(document_type: "transcript").count
    end
  end
end
