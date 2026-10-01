namespace :crawlers do
  desc "Refresh verified crawler IP ranges from the operators' official feeds"
  task refresh: :environment do
    Crawlers::RefreshIpRangesJob.perform_now
  end

  desc "Create public and gated synthetic crawler probes which expire in 48 hours"
  task probes: :environment do
    probes = Crawlers::Probe.create_pair.transform_values do |probe|
      url = Rails.application.routes.url_helpers.crawler_probe_url(
        token: probe.fetch(:token), host: ENV.fetch("APP_HOST", "localhost"),
        protocol: Rails.env.production? ? "https" : "http"
      )
      probe.merge(url: url, expires_at: Time.at(probe.fetch(:expires_at)).utc.iso8601)
    end
    puts JSON.pretty_generate(probes)
  end
end
