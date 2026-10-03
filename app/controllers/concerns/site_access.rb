module SiteAccess
  extend ActiveSupport::Concern

  included do
    helper_method :gated_for_visitor?, :site_gated?, :crawler_readable_page?
    before_action :prevent_gated_response_caching
  end

  CRAWLER_READABLE_ACTIONS = {
    "home" => %w[index],
    "topics" => %w[index show],
    "meetings" => %w[index show],
    "committees" => %w[show],
    "members" => %w[show],
    "crawler_probes" => %w[show],
    "sitemaps" => %w[show]
  }.freeze

  private

    # Memoized per request. CurrentAttributes is reset between requests, so
    # this is one query per request rather than one per call site.
    def site_gated?
      Current.site_access_mode ||= SiteSetting.access_mode
      Current.site_access_mode == "gated"
    end

    def gated_for_visitor?
      site_gated? && !authenticated? && !verified_crawler?
    end

    def crawler_readable_page?
      CRAWLER_READABLE_ACTIONS.fetch(controller_path, []).include?(action_name)
    end

    def verified_crawler?
      return false unless crawler_readable_page?
      return @verified_crawler if defined?(@verified_crawler)

      outcome = Crawlers::Verifier.new.outcome(request)
      readable = crawler_readable_format?
      @verified_crawler = outcome.bot.present? && readable
      log_crawler_rejection(outcome) unless @verified_crawler
      @verified_crawler
    end

    # Rails treats a bare `Accept: */*` as format `*/*`, not HTML. The HTML
    # template still renders, so that request is the ordinary page. An
    # explicit format such as turbo_stream stays closed.
    def crawler_readable_format?
      expected = controller_path == "sitemaps" ? Mime[:xml] : Mime[:html]
      request.format == expected || request.format == Mime::ALL
    end

    def log_crawler_rejection(outcome)
      reason = outcome.reason
      reason = "format" if reason.nil? && outcome.bot.present?
      return if reason.blank?

      Rails.logger.info("Crawler verification rejected ip=#{outcome.ip.presence || "-"} reason=#{reason}")
    end

    def prevent_gated_response_caching
      # The same URL can contain full reporting for a verified crawler and a
      # teaser for a human. Neither response may enter a shared/browser cache.
      response.headers["Cache-Control"] = "private, no-store" if site_gated? && crawler_readable_page?
    end
end
