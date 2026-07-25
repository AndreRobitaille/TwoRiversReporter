module SiteAccess
  extend ActiveSupport::Concern

  included do
    helper_method :gated_for_visitor?, :site_gated?
  end

  private

    # Memoized per request. CurrentAttributes is reset between requests, so
    # this is one query per request rather than one per call site.
    def site_gated?
      Current.site_access_mode ||= SiteSetting.access_mode
      Current.site_access_mode == "gated"
    end

    def gated_for_visitor?
      site_gated? && !authenticated?
    end
end
