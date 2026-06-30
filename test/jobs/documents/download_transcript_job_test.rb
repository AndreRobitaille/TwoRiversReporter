require "test_helper"

module Documents
  class DownloadTranscriptJobTest < ActiveJob::TestCase
    include ActiveJob::TestHelper

    def setup
      @meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.zone.local(2026, 3, 15, 18, 0, 0), status: "held", detail_page_url: "http://example.com/meetings/transcript-test-#{SecureRandom.hex(4)}")
      @video_url = "https://www.youtube.com/watch?v=abc123"
    end

    test "enqueues summary after created transcript when no minutes recap exists" do
      result = Documents::TranscriptDownloader::Result.new(status: "created", meeting_document: nil)
      downloader = Object.new
      downloader.define_singleton_method(:download_and_store) { result }

      Documents::TranscriptDownloader.stub :new, downloader do
        assert_enqueued_with(job: SummarizeMeetingJob, args: [ @meeting.id ]) do
          DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
        end
      end
    end

    test "does not enqueue summary when minutes recap exists" do
      MeetingSummary.create!(meeting: @meeting, summary_type: "minutes_recap", content: "Existing minutes recap")
      result = Documents::TranscriptDownloader::Result.new(status: "created", meeting_document: nil)
      downloader = Object.new
      downloader.define_singleton_method(:download_and_store) { result }

      Documents::TranscriptDownloader.stub :new, downloader do
        assert_no_enqueued_jobs(only: SummarizeMeetingJob) do
          DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
        end
      end
    end

    test "does not enqueue summary when transcript is reused" do
      result = Documents::TranscriptDownloader::Result.new(status: "reused", meeting_document: MeetingDocument.new)
      downloader = Object.new
      downloader.define_singleton_method(:download_and_store) { result }

      Documents::TranscriptDownloader.stub :new, downloader do
        assert_no_enqueued_jobs(only: SummarizeMeetingJob) do
          DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
        end
      end
    end

    test "logs and does not raise on invalid URL errors" do
      downloader = Object.new
      downloader.define_singleton_method(:download_and_store) { raise Documents::TranscriptDownloader::InvalidUrlError, "Invalid YouTube URL" }

      Rails.logger.stub :error, nil do
        Documents::TranscriptDownloader.stub :new, downloader do
          assert_nothing_raised do
            DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
          end
        end
      end
    end

    test "logs and does not raise on download errors" do
      downloader = Object.new
      downloader.define_singleton_method(:download_and_store) { raise Documents::TranscriptDownloader::DownloadError, "yt-dlp failed" }

      Rails.logger.stub :error, nil do
        Documents::TranscriptDownloader.stub :new, downloader do
          assert_nothing_raised do
            DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
          end
        end
      end
    end
  end
end
