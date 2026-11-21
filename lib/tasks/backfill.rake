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

  desc "Re-enqueue AI pipeline (topics, votes, members, summaries) for all meetings with extracted text since 2025-01-01"
  task reprocess: :environment do
    since = Date.new(2025, 1, 1)
    meetings = Meeting.where("starts_at >= ?", since)
                      .joins(:meeting_documents)
                      .where.not(meeting_documents: { extracted_text: nil })
                      .distinct

    # Clear any stale failed jobs before starting fresh
    failed_count = SolidQueue::FailedExecution.count rescue 0
    if failed_count > 0
      puts "Clearing #{failed_count} failed jobs..."
      SolidQueue::FailedExecution.delete_all
    end

    count = meetings.count
    puts "Re-enqueuing AI pipeline for #{count} meetings with extracted text since #{since}..."

    meetings.find_each.with_index do |meeting, i|
      ExtractTopicsJob.perform_later(meeting.id)
      ExtractVotesJob.perform_later(meeting.id)
      ExtractCommitteeMembersJob.perform_later(meeting.id)
      SummarizeMeetingJob.perform_later(meeting.id)
      puts "  Enqueued #{i + 1}/#{count}: #{meeting.body_name} (#{meeting.starts_at&.to_date})" if (i + 1) % 10 == 0
    end

    puts "Done. #{count * 4} jobs enqueued. Monitor with: bin/rails backfill:status"
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

  desc "Read the city listings for FROM..THROUGH and compare with this database; optional BODY"
  task preview: :environment do
    inventory = CouncilHistory::Inventory.new(from: Date.iso8601(ENV.fetch("FROM")),
      through: Date.iso8601(ENV.fetch("THROUGH")), body: ENV["BODY"])
    rows = CouncilHistory::Inventory.review(inventory.listings)
    facts = ENV["REVIEWED_FACTS"] ? JSON.parse(File.read(ENV.fetch("REVIEWED_FACTS"))) : []
    estimate = CouncilHistory::Estimate.call(rows, from: Date.iso8601(ENV.fetch("FROM")),
      through: Date.iso8601(ENV.fetch("THROUGH")), reviewed_facts: facts)
    puts JSON.generate(listings: rows, estimate: estimate)
  end

  desc "Run or resume named historical stages for FROM..THROUGH, optional BODY, PHASE=pilot or full"
  task scoped: :environment do
    phase = ENV.fetch("PHASE")
    raise ArgumentError, "Specify pilot or full" unless phase.in?(%w[pilot full])
    from, through = %w[FROM THROUGH].map { |key| Date.iso8601(ENV.fetch(key)) }
    raise ArgumentError, "Outside historical window" unless from >= CouncilHistory::Batch::FIRST && through <= CouncilHistory::Batch::LAST
    Campaigns::LivePricing::SECTIONS.each_key { |model| Campaigns::LivePricing.refresh_model(model) }
    inventory = CouncilHistory::Inventory.new(from: from, through: through, body: ENV["BODY"])
    facts = ENV["REVIEWED_FACTS"] ? JSON.parse(File.read(ENV.fetch("REVIEWED_FACTS"))) : []
    comparisons = JSON.parse(File.read(ENV.fetch("COMPARISON_FILE")))
    actor = User.usable_admins.find(ENV.fetch("ACTOR_ID"))
    listings = inventory.listings
    listings.reject! { |row| row.fetch("title").match?(/council/i) } if phase == "full" && ENV["SKIP_COUNCIL"] == "1"
    CouncilHistory::Batch.new(listings, pilot: phase == "pilot", reviewed_facts: facts,
      reviewed_comparisons: comparisons, actor: actor, pilot_reuse_url: ENV["PILOT_REUSE_URL"]).call do |result|
      puts JSON.generate(result)
      $stdout.flush
    end
  end

  desc "Fill missing topic briefings after completing the selected historical meeting batches"
  task finish_briefings: :environment do
    from, through = %w[FROM THROUGH].map { |key| Date.iso8601(ENV.fetch(key)) }
    Campaigns::LivePricing::SECTIONS.each_key { |model| Campaigns::LivePricing.refresh_model(model) }
    CouncilHistory::Batch.finish_briefings(from: from, through: through) do |result|
      puts JSON.generate(result)
      $stdout.flush
    end
  end

  desc "Repair specific later stages using saved records for one MEETING_ID and comma-separated STAGES"
  task repair_saved: :environment do
    meeting = Meeting.find(ENV.fetch("MEETING_ID"))
    stages = ENV.fetch("STAGES").split(",")
    facts = ENV["REVIEWED_FACTS"] ? JSON.parse(File.read(ENV.fetch("REVIEWED_FACTS"))) : []
    comparisons = JSON.parse(File.read(ENV.fetch("COMPARISON_FILE")))
    actor = User.usable_admins.find(ENV.fetch("ACTOR_ID"))
    Campaigns::LivePricing::SECTIONS.each_key { |model| Campaigns::LivePricing.refresh_model(model) }
    batch = CouncilHistory::Batch.new([], reviewed_facts: facts, reviewed_comparisons: comparisons, actor: actor)
    puts JSON.generate(batch.repair_saved(meeting, stages: stages))
  end

  desc "Refresh the dated Council coverage disclosure from the city index and this database"
  task publish_coverage: :environment do
    puts JSON.generate(CouncilHistory::Coverage.refresh!(full: true).except("listings"))
  end
end
