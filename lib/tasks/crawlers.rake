namespace :crawlers do
  desc "Refresh verified crawler IP ranges from the operators' official feeds"
  task refresh: :environment do
    Crawlers::RefreshIpRangesJob.perform_now
  end
end
