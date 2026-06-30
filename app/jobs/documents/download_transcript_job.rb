module Documents
  class DownloadTranscriptJob < ApplicationJob
    queue_as :default

    def perform(meeting_id, video_url)
      meeting = Meeting.find(meeting_id)
      downloader = Documents::TranscriptDownloader.new(meeting: meeting, video_url: video_url)
      result = downloader.download_and_store

      if result.created?
        Rails.logger.info "DownloadTranscriptJob: created transcript for meeting #{meeting.id}"
      else
        Rails.logger.info "DownloadTranscriptJob: reused existing transcript for meeting #{meeting.id}"
      end

      if result.created? && !meeting.meeting_summaries.exists?(summary_type: "minutes_recap")
        SummarizeMeetingJob.perform_later(meeting.id)
      end
    rescue Documents::TranscriptDownloader::InvalidUrlError => e
      Rails.logger.error "DownloadTranscriptJob: #{e.message} for #{video_url}"
    rescue Documents::TranscriptDownloader::DownloadError => e
      Rails.logger.error "DownloadTranscriptJob: #{e.message} for #{video_url}"
    end
  end
end
