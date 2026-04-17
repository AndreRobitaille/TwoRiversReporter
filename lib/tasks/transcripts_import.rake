namespace :transcripts do
  desc "Import SRT files from a directory into MeetingDocument records. " \
       "Files: <meeting_id>_<date>.en.srt or <meeting_id>_<date>_<video_id>.en.srt"
  task :import, [ :dir ] => :environment do |_t, args|
    dir = args[:dir]
    abort "Usage: bin/rails transcripts:import[/path/to/srt/files]" unless dir.present?
    abort "Directory not found: #{dir}" unless Dir.exist?(dir)

    srt_files = Dir.glob(File.join(dir, "*.srt")).sort
    puts "Found #{srt_files.size} SRT files in #{dir}"
    puts

    imported = 0
    skipped = 0

    srt_files.each do |srt_path|
      filename = File.basename(srt_path)
      match = filename.match(/\A(\d+)_(\d{4}-\d{2}-\d{2})(?:_([A-Za-z0-9_-]+))?\.en\.srt\z/)
      unless match
        puts "SKIP  #{filename} — doesn't match expected naming pattern"
        skipped += 1
        next
      end

      meeting_id = match[1].to_i
      video_id = match[3] # nil if old format without video ID
      meeting = Meeting.find_by(id: meeting_id)
      unless meeting
        puts "SKIP  #{filename} — no Meeting with id #{meeting_id}"
        skipped += 1
        next
      end

      if meeting.meeting_documents.exists?(document_type: "transcript")
        puts "SKIP  #{filename} — meeting #{meeting_id} already has a transcript"
        skipped += 1
        next
      end

      srt_content = File.read(srt_path)
      plain_text = srt_content
        .gsub(/^\d+\s*$/, "")
        .gsub(/^\d{2}:\d{2}:\d{2},\d{3}\s*-->.*$/, "")
        .gsub(/\n{3,}/, "\n\n")
        .strip

      source_url = if video_id
        "https://www.youtube.com/watch?v=#{video_id}"
      else
        puts "WARN  #{filename} — no video ID in filename, URL will be a placeholder"
        "https://www.youtube.com/watch?v=imported"
      end

      doc = meeting.meeting_documents.create!(
        document_type: "transcript",
        source_url: source_url,
        extracted_text: plain_text,
        text_quality: "auto_transcribed",
        text_chars: plain_text.length,
        fetched_at: Time.current
      )

      doc.file.attach(
        io: File.open(srt_path),
        filename: "transcript-#{meeting.starts_at.to_date}.srt",
        content_type: "text/srt"
      )

      puts "OK    #{filename} — meeting #{meeting_id} (#{meeting.body_name}, #{meeting.starts_at.to_date}) — #{plain_text.length} chars"
      imported += 1

      # Enqueue summarization if no minutes-based summary
      unless meeting.meeting_summaries.exists?(summary_type: "minutes_recap")
        SummarizeMeetingJob.perform_later(meeting.id)
        puts "      -> Enqueued SummarizeMeetingJob"
      end
    end

    puts
    puts "Import complete: #{imported} imported, #{skipped} skipped"
  end

  desc "Backfill real YouTube URLs for transcript documents with placeholder source_url"
  task backfill_urls: :environment do
    require "open3"

    placeholder_docs = MeetingDocument
      .where(document_type: "transcript", source_url: "https://www.youtube.com/watch?v=imported")
      .includes(:meeting)

    if placeholder_docs.empty?
      puts "No placeholder transcript URLs to fix."
      next
    end

    puts "Found #{placeholder_docs.count} transcripts with placeholder URLs"
    puts "Fetching YouTube channel video list..."

    stdout, stderr, status = Open3.capture3(
      "yt-dlp", "--flat-playlist", "--print", "%(id)s | %(title)s",
      "https://www.youtube.com/@Two_Rivers_WI/streams"
    )

    unless status.success?
      abort "yt-dlp failed: #{stderr.strip}"
    end

    title_pattern = /(?:City Council (?:Meeting|Work Session)) for \w+, (.+)$/i
    videos = stdout.lines.filter_map do |line|
      id, title = line.strip.split(" | ", 2)
      next unless id.present? && title.present?
      date_match = title_pattern.match(title)
      next unless date_match
      parsed_date = Date.parse(date_match[1].strip) rescue nil
      next unless parsed_date
      [ parsed_date, id, title ]
    end

    puts "Found #{videos.size} matching videos on channel"
    puts

    fixed = 0
    placeholder_docs.each do |doc|
      meeting = doc.meeting
      meeting_date = meeting.starts_at&.to_date
      next unless meeting_date

      match = videos.find { |date, _, _| date == meeting_date }
      if match
        _, video_id, video_title = match
        real_url = "https://www.youtube.com/watch?v=#{video_id}"
        doc.update!(source_url: real_url)
        puts "FIXED Meeting #{meeting.id} (#{meeting_date}) -> #{real_url}"
        puts "      #{video_title}"
        fixed += 1
      else
        puts "MISS  Meeting #{meeting.id} (#{meeting.body_name}, #{meeting_date}) — no matching video found"
      end
    end

    puts
    unmatched = placeholder_docs.size - fixed
    puts "Backfill complete: #{fixed} fixed, #{unmatched} unmatched"
  end
end
