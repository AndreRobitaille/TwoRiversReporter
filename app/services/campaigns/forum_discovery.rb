module Campaigns
  class ForumDiscovery
    LEAGUE = "League of Women Voters"
    BUSINESS = "Two Rivers Business Association"
    NOTICE = /\b(League of Women Voters|Two Rivers Business Association),?\s+(?:Two Rivers )?City Council Candidates? Forum,?\s+(?:\w+day,?\s+)?((?:February|March|April)\s+\d{1,2},\s+\d{4})\b/i
    CHANNEL_SEARCH = "https://www.youtube.com/@Two_Rivers_WI/search?query=forum"

    def self.collect_notices(election_on, through:)
      season = Date.new(election_on.year, 2, 1)..election_on
      documents = MeetingDocument.joins(:meeting).where(document_type: %w[agenda_pdf minutes_pdf],
        meetings: { body_name: "City Council Meeting", starts_at: season.begin.beginning_of_day..through.end_of_day })
        .where("extracted_text ILIKE ?", "%forum%").order("meetings.starts_at", :id)
      documents.pluck(:source_url, :extracted_text).each do |url, text|
        next unless url.to_s.start_with?("https://")
        text.squish.scan(NOTICE).each do |name, date|
          held_on = Date.strptime(date, "%B %e, %Y")
          next unless season.cover?(held_on)
          ElectionForum.find_or_create_by!(election_on: election_on, held_on: held_on, organizer: organizer(name)) do |forum|
            forum.announcement_url = url
          end
        rescue Date::Error
          next
        end
      end
    end

    def self.collect_recordings(forums)
      return if forums.empty?
      listings.each_line do |line|
        id, title = line.chomp.split(" | ", 2)
        next unless id&.match?(/\A[A-Za-z0-9_-]{11}\z/) && title.to_s.match?(/\bcandidates? forum\b/i)
        next if title.match?(/school board|board of education/i)
        possible = forums.select { |forum| forum.organizer == organizer(title) }
        next if possible.empty? || possible.any? { |forum| forum.recordings.key?(id) }
        started_at = broadcast_start(id)
        next unless started_at
        forum = possible.find { |event| event.held_on == started_at.in_time_zone.to_date }
        next unless forum
        forum.with_lock do
          forum.update!(recordings: forum.recordings.merge(id => { "title" => title, "started_at" => started_at.utc.iso8601 }))
        end
      end
    end

    def self.organizer(title)
      return LEAGUE if title.match?(/League of Women/i)
      BUSINESS if title.match?(/Two Rivers Business Association|\bTRBA\b/i)
    end

    def self.listings
      cli = Documents::TranscriptDownloader
      output, error, status = cli.run_yt_dlp(*cli.yt_dlp_args, "--ignore-config", "--flat-playlist",
        "--playlist-end", "50", "--socket-timeout", "10", "--retries", "0", "--extractor-retries", "0",
        "--print", "%(id)s | %(title)s", CHANNEL_SEARCH)
      raise cli::DownloadError, error unless status.success?
      output
    end

    def self.broadcast_start(video_id)
      Rails.cache.fetch("forum-broadcast-start/#{video_id}", expires_in: 90.days, skip_nil: true) do
        response = Faraday.get(ElectionForum.video_url(video_id)) do |request|
          request.options.open_timeout = 5
          request.options.timeout = 12
        end
        next unless response.success?
        page = Nokogiri::HTML(response.body)
        start = page.at_css('meta[itemprop="startDate"]')&.[]("content")
        Time.iso8601(start) if start && page.at_css('meta[itemprop="endDate"]')
      end
    rescue Faraday::Error, ArgumentError => error
      Rails.logger.info("Forum recording #{video_id} could not be dated: #{error.message}")
      nil
    end
  end
end
