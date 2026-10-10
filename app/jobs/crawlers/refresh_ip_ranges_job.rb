module Crawlers
  class RefreshIpRangesJob < ApplicationJob
    queue_as :default
    retry_on IpRanges::Error, wait: :polynomially_longer, attempts: 3

    def perform
      ranges = IpRanges.new
      failures = []

      Providers::FEEDS.each_key do |feed|
        begin
          count = ranges.refresh(feed)
          Rails.logger.info("Crawler ranges refreshed: #{feed} (#{count} prefixes)")
        rescue IpRanges::Error => error
          Rails.logger.error("Crawler range refresh failed: #{feed} (#{error.message})")
          failures << feed
        end
      end

      raise IpRanges::Error, "failed feeds: #{failures.join(', ')}" if failures.any?
    end
  end
end
