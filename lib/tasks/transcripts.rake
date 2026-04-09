namespace :transcripts do
  desc "Backfill transcripts for council meetings/work sessions in a date range"
  task :backfill, [ :since, :until ] => :environment do |_t, args|
    require "open3"

    since_date = args[:since] ? Date.parse(args[:since]) : 90.days.ago.to_date
    until_date = args[:until] ? Date.parse(args[:until]) : Date.current

    puts "Fetching YouTube video list..."
    stdout, stderr, status = Open3.capture3(
      "yt-dlp", "--flat-playlist", "--print", "%(id)s | %(title)s",
      Scrapers::DiscoverTranscriptsJob::YOUTUBE_CHANNEL_URL
    )

    unless status.success?
      puts "ERROR: yt-dlp failed: #{stderr}"
      exit 1
    end

    pattern = Scrapers::DiscoverTranscriptsJob::TITLE_PATTERN
    video_map = {}
    stdout.each_line do |line|
      id, title = line.strip.split(" | ", 2)
      next unless id.present? && title.present?
      match = title.match(pattern)
      next unless match
      date = Date.parse(match[1]) rescue nil
      next unless date
      video_map[date] = [ id, title ]
    end

    puts "Found #{video_map.size} parseable council/work session videos"

    meetings = Meeting
      .where(body_name: Scrapers::DiscoverTranscriptsJob::COUNCIL_BODY_NAMES)
      .where("starts_at >= ? AND starts_at <= ?", since_date, until_date.end_of_day)
      .includes(:meeting_documents)
      .order(starts_at: :asc)

    puts "Found #{meetings.size} meetings from #{since_date} to #{until_date}"
    puts

    downloaded = 0
    skipped = 0
    missed = 0

    meetings.each do |m|
      has_transcript = m.meeting_documents.any? { |d| d.document_type == "transcript" }
      if has_transcript
        puts "SKIP  #{m.id} | #{m.starts_at.to_date} | #{m.body_name} — already has transcript"
        skipped += 1
        next
      end

      video = video_map[m.starts_at.to_date]
      unless video
        puts "MISS  #{m.id} | #{m.starts_at.to_date} | #{m.body_name} — no YouTube match"
        missed += 1
        next
      end

      vid_id, title = video
      url = "https://www.youtube.com/watch?v=#{vid_id}"
      puts "FETCH #{m.id} | #{m.starts_at.to_date} | #{m.body_name}"
      puts "      -> #{title}"
      begin
        Documents::DownloadTranscriptJob.perform_now(m.id, url)
        puts "      -> Done"
        downloaded += 1
      rescue => e
        puts "      -> ERROR: #{e.message}"
      end
    end

    puts
    puts "Backfill complete: #{downloaded} downloaded, #{skipped} skipped, #{missed} no match"
  end
end
