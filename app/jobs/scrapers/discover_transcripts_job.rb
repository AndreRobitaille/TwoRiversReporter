require "open3"

module Scrapers
  class DiscoverTranscriptsJob < ApplicationJob
    queue_as :default

    YOUTUBE_CHANNEL_URL = "https://www.youtube.com/@Two_Rivers_WI/streams"
    TITLE_PATTERN = /(?:City Council (?:Meeting|Work Session)) for \w+, (.+)$/i
    COUNCIL_BODY_NAMES = [ "City Council Meeting", "City Council Work Session" ].freeze
    LOOKBACK_WINDOW = 48.hours

    def perform
      meetings = candidate_meetings
      return if meetings.empty?

      videos = fetch_video_list
      return if videos.nil?

      videos.each do |video_id, title|
        match = TITLE_PATTERN.match(title)
        next unless match

        date_str = match[1].strip
        parsed_date = parse_date(date_str)
        next unless parsed_date

        meeting = find_meeting(meetings, parsed_date)
        next unless meeting

        video_url = "https://www.youtube.com/watch?v=#{video_id}"
        Documents::DownloadTranscriptJob.perform_later(meeting.id, video_url)
      end
    end

    private

    def candidate_meetings
      Meeting
        .where(body_name: COUNCIL_BODY_NAMES)
        .where("starts_at >= ? AND starts_at <= ?", LOOKBACK_WINDOW.ago, Time.current)
        .includes(:meeting_documents)
        .reject { |m| m.meeting_documents.any? { |d| d.document_type == "transcript" } }
    end

    def fetch_video_list
      stdout, stderr, status = Open3.capture3(
        "yt-dlp", "--flat-playlist", "--print", "%(id)s | %(title)s",
        YOUTUBE_CHANNEL_URL
      )

      unless status.success?
        Rails.logger.error "DiscoverTranscriptsJob: yt-dlp failed — #{stderr.strip}"
        return nil
      end

      stdout.lines.filter_map do |line|
        id, title = line.strip.split(" | ", 2)
        next unless id.present? && title.present?

        [ id, title ]
      end
    end

    def parse_date(date_str)
      Date.parse(date_str)
    rescue ArgumentError, TypeError
      nil
    end

    def find_meeting(meetings, date)
      meetings.find { |m| m.starts_at.to_date == date }
    end
  end
end
