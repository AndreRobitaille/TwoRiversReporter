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
    "members" => %w[show]
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
      return false unless crawler_readable_page? && request.format == Mime[:html]
      return @verified_crawler if defined?(@verified_crawler)

      @verified_crawler = Crawlers::Verifier.new.call(request).present?
    end

    def prevent_gated_response_caching
      # The same URL can contain full reporting for a verified crawler and a
      # teaser for a human. Neither response may enter a shared/browser cache.
      response.headers["Cache-Control"] = "private, no-store" if site_gated? && crawler_readable_page?
    end
end
