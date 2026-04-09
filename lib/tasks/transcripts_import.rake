namespace :transcripts do
  desc "Import SRT files from a directory into MeetingDocument records. Files must be named <meeting_id>_<date>.en.srt"
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
      match = filename.match(/\A(\d+)_(\d{4}-\d{2}-\d{2})\.en\.srt\z/)
      unless match
        puts "SKIP  #{filename} — doesn't match expected naming pattern"
        skipped += 1
        next
      end

      meeting_id = match[1].to_i
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

      doc = meeting.meeting_documents.create!(
        document_type: "transcript",
        source_url: "https://www.youtube.com/watch?v=imported",
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
end
