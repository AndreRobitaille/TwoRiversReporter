namespace :meetings do
  desc "Clean obvious duplicate meetings in the meetings page window (DRY_RUN=true by default)"
  task cleanup_window_duplicates: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    report = Meetings::WindowDuplicateCleanup.call(dry_run: dry_run)

    puts dry_run ? "DRY RUN — no meetings deleted" : "Deleted duplicate meetings"
    puts "Kept meeting ids: #{report[:kept_ids].join(', ')}"
    puts "Deleted meeting ids: #{report[:deleted_ids].join(', ')}"
    puts "Skipped duplicate groups: #{report[:skipped_groups].map { |ids| ids.join('/') }.join(', ')}"
  end
end
