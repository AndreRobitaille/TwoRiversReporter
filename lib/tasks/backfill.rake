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
end
