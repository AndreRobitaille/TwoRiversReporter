require "test_helper"
require "ostruct"
require "open3"

module Documents
  class DownloadTranscriptJobTest < ActiveJob::TestCase
    include ActiveJob::TestHelper

    SAMPLE_SRT = <<~SRT
      1
      00:00:01,000 --> 00:00:03,000
      Welcome to the city council meeting.

      2
      00:00:04,000 --> 00:00:06,500
      Tonight we will discuss the budget proposal.

      3
      00:00:07,000 --> 00:00:09,000
      Public input is now open.

    SRT

    def setup
      @meeting = Meeting.create!(
        body_name: "City Council",
        meeting_type: "Regular",
        starts_at: Time.zone.local(2026, 3, 15, 18, 0, 0),
        status: "held",
        detail_page_url: "http://example.com/meetings/transcript-test-#{SecureRandom.hex(4)}"
      )
      @video_url = "https://www.youtube.com/watch?v=abc123"
    end

    # Stubs Dir.mktmpdir("transcript") to yield a real tmpdir that already has the SRT file.
    # Restores Dir.mktmpdir after the block.
    def stub_yt_dlp(srt_content)
      Dir.mktmpdir("test-transcript") do |tmpdir|
        srt_path = File.join(tmpdir, "video.en.srt")
        File.write(srt_path, srt_content)

        original_mktmpdir = Dir.method(:mktmpdir)
        Dir.define_singleton_method(:mktmpdir) do |*args, &block|
          if args.first == "transcript"
            block.call(tmpdir)
          else
            original_mktmpdir.call(*args, &block)
          end
        end

        Open3.stub :capture3, [ "", "", OpenStruct.new(success?: true) ] do
          yield
        end
      ensure
        Dir.define_singleton_method(:mktmpdir, original_mktmpdir)
      end
    end

    # -----------------------------------------------------------------------
    # Test 1: creates MeetingDocument with correct attributes and file attached
    # -----------------------------------------------------------------------
    test "downloads transcript and creates MeetingDocument" do
      stub_yt_dlp(SAMPLE_SRT) do
        assert_difference "MeetingDocument.count", 1 do
          DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
        end
      end

      doc = @meeting.meeting_documents.find_by!(document_type: "transcript")
      assert_equal @video_url, doc.source_url
      assert_equal "auto_transcribed", doc.text_quality
      assert_not_includes doc.extracted_text, "00:00:01,000 --> 00:00:03,000", "SRT timestamps must be stripped"
      refute_match(/^\d+\s*$/, doc.extracted_text, "SRT sequence numbers must be stripped")
      assert_includes doc.extracted_text, "Welcome to the city council meeting."
      assert_includes doc.extracted_text, "Tonight we will discuss the budget proposal."
      assert_operator doc.text_chars, :>, 0
      assert_not_nil doc.fetched_at
      assert doc.file.attached?, "SRT file should be attached"
    end

    # -----------------------------------------------------------------------
    # Test 2: skips if transcript document already exists
    # -----------------------------------------------------------------------
    test "skips if meeting already has a transcript document" do
      MeetingDocument.create!(
        meeting: @meeting,
        document_type: "transcript",
        source_url: @video_url,
        text_quality: "auto_transcribed",
        extracted_text: "existing transcript"
      )

      stub_yt_dlp(SAMPLE_SRT) do
        assert_no_difference "MeetingDocument.count" do
          DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
        end
      end
    end

    # -----------------------------------------------------------------------
    # Test 3: enqueues SummarizeMeetingJob when no minutes_recap summary
    # -----------------------------------------------------------------------
    test "enqueues SummarizeMeetingJob when no minutes_recap summary exists" do
      stub_yt_dlp(SAMPLE_SRT) do
        assert_enqueued_with(job: SummarizeMeetingJob, args: [ @meeting.id ]) do
          DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
        end
      end
    end

    # -----------------------------------------------------------------------
    # Test 4: does not enqueue SummarizeMeetingJob when minutes_recap exists
    # -----------------------------------------------------------------------
    test "does not enqueue SummarizeMeetingJob when minutes_recap summary exists" do
      MeetingSummary.create!(
        meeting: @meeting,
        summary_type: "minutes_recap",
        content: "Existing minutes recap"
      )

      stub_yt_dlp(SAMPLE_SRT) do
        assert_no_enqueued_jobs(only: SummarizeMeetingJob) do
          DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
        end
      end
    end

    # -----------------------------------------------------------------------
    # Test 5: handles yt-dlp failure gracefully (no document created)
    # -----------------------------------------------------------------------
    test "handles yt-dlp failure gracefully without creating a document" do
      original_mktmpdir = Dir.method(:mktmpdir)
      Dir.define_singleton_method(:mktmpdir) do |*args, &block|
        if args.first == "transcript"
          Dir.mktmpdir("test-transcript-fail") do |tmpdir|
            # No SRT file written — yt-dlp "failed"
            block.call(tmpdir)
          end
        else
          original_mktmpdir.call(*args, &block)
        end
      end

      begin
        Open3.stub :capture3, [ "", "ERROR: Unable to download", OpenStruct.new(success?: false) ] do
          assert_no_difference "MeetingDocument.count" do
            DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
          end
        end
      ensure
        Dir.define_singleton_method(:mktmpdir, original_mktmpdir)
      end
    end
  end
end
