require "open3"

module Documents
  class DownloadTranscriptJob < ApplicationJob
    queue_as :default

    def perform(meeting_id, video_url)
      meeting = Meeting.find(meeting_id)

      # Idempotency: skip if transcript already exists
      return if meeting.meeting_documents.exists?(document_type: "transcript")

      srt_content, plain_text = download_captions(video_url)
      return unless plain_text

      document = meeting.meeting_documents.create!(
        document_type: "transcript",
        source_url: video_url,
        extracted_text: plain_text,
        text_quality: "auto_transcribed",
        text_chars: plain_text.length,
        fetched_at: Time.current
      )

      document.file.attach(
        io: StringIO.new(srt_content),
        filename: "transcript-#{meeting.starts_at.to_date}.srt",
        content_type: "text/srt"
      )

      unless meeting.meeting_summaries.exists?(summary_type: "minutes_recap")
        SummarizeMeetingJob.perform_later(meeting.id)
      end
    end

    private

    def download_captions(video_url)
      Dir.mktmpdir("transcript") do |tmpdir|
        stdout, stderr, status = Open3.capture3(
          "yt-dlp",
          "--write-auto-sub",
          "--sub-lang", "en",
          "--sub-format", "srt",
          "--skip-download",
          "-o", "#{tmpdir}/video",
          video_url
        )

        unless status.success?
          Rails.logger.error "yt-dlp failed for #{video_url}: #{stderr.strip}"
          return nil
        end

        srt_files = Dir.glob("#{tmpdir}/*.srt")
        if srt_files.empty?
          Rails.logger.error "yt-dlp produced no SRT file for #{video_url}"
          return nil
        end

        srt_content = File.read(srt_files.first)
        plain_text = parse_srt(srt_content)
        [ srt_content, plain_text ]
      end
    end

    def parse_srt(srt_content)
      srt_content
        .gsub(/^\d+\s*$/, "")
        .gsub(/^\d{2}:\d{2}:\d{2},\d{3}\s*-->.*$/, "")
        .gsub(/\n{3,}/, "\n\n")
        .strip
    end
  end
end
