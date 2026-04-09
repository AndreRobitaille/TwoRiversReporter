namespace :backfill do
  desc "One-time backfill: discover all meetings since 2025-01-01 and run the full pipeline"
  task run: :environment do
    since = Date.new(2025, 1, 1)
    puts "Starting backfill: discovering meetings since #{since}..."
    puts "This will enqueue ParseMeetingPageJob for each meeting found."
    puts "The full pipeline (download → extract → topics → votes → members → summarize) runs automatically."
    puts ""

    Scrapers::DiscoverMeetingsJob.perform_later(since: since)

    puts "DiscoverMeetingsJob enqueued. Monitor progress with: bin/rails backfill:status"
  end

  desc "Show backfill pipeline progress"
  task status: :environment do
    since = Date.new(2025, 1, 1)
    meetings = Meeting.where("starts_at >= ?", since)

    total = meetings.count
    with_docs = meetings.joins(:meeting_documents).distinct.count
    with_minutes = meetings.joins(:meeting_documents).where(meeting_documents: { document_type: "minutes_pdf" }).distinct.count
    with_text = meetings.joins(:meeting_documents).where.not(meeting_documents: { extracted_text: nil }).distinct.count
    with_topics = meetings.joins(:topics).distinct.count
    with_summaries = meetings.joins(:meeting_summaries).distinct.count

    # Solid Queue job counts (pending/in-progress) — in a separate DB, handle connection errors gracefully
    pending_jobs = SolidQueue::Job.where(finished_at: nil).count rescue "N/A"
    failed_jobs = SolidQueue::FailedExecution.count rescue "N/A"

    puts ""
    puts "=== Backfill Pipeline Status ==="
    puts "Meetings since #{since}"
    puts "-" * 40
    puts "Total meetings:        #{total}"
    puts "With any documents:    #{with_docs}"
    puts "With minutes PDF:      #{with_minutes}"
    puts "With extracted text:   #{with_text}"
    puts "With topics:           #{with_topics}"
    puts "With summaries:        #{with_summaries}"
    puts "-" * 40
    puts "Pending jobs:          #{pending_jobs}"
    puts "Failed jobs:           #{failed_jobs}"
    puts ""

    if failed_jobs.is_a?(Integer) && failed_jobs > 0
      puts "⚠  Failed jobs detected. Check with: bin/rails runner 'SolidQueue::FailedExecution.last(10).each { |f| puts \"#{f.job.class_name}: #{f.error.to_s.truncate(120)}\" }'"
    end

    if pending_jobs.is_a?(Integer) && pending_jobs > 0
      # Show job type breakdown
      puts "Pending job breakdown:"
      SolidQueue::Job.where(finished_at: nil).group(:class_name).count.sort_by { |_, v| -v }.each do |class_name, count|
        puts "  #{class_name}: #{count}"
      end
    end

    puts ""
  end
end
