module SiteAccess
  extend ActiveSupport::Concern

  included do
    helper_method :gated_for_visitor?, :site_gated?

    # The mode must participate in the etag, or a page cached while the site
    # was open keeps being served after a flip to gated. Calling site_gated?
    # here also populates the per-request memo.
    #
    # Registering the block alone is not enough: Rails only folds
    # `etaggers` into a response inside #fresh_when/#stale? (see
    # ActionController::ConditionalGet#combine_etags), and nothing in this
    # app calls either. The after_action below is what actually applies it,
    # using the rendered body as the base validator so we keep the same
    # content-sensitivity Rack::ETag would otherwise provide and only add
    # gating on top of it.
    etag { site_gated? }
    after_action :compose_site_access_etag
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

    def compose_site_access_etag
      return unless request.format&.html?
      return if response.etag? || response.body.blank?

      response.weak_etag = combine_etags(ActiveSupport::Digest.hexdigest(response.body), {})
    end
end
