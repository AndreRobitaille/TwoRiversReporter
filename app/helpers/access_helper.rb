module AccessHelper
  # Fallback meta description. Home and About override it; every other page
  # and the sitewide Organization node reuse this sentence.
  DEFAULT_SITE_DESCRIPTION = "A plain-language guide to the Two Rivers, WI city government — what's being decided, what keeps coming back, and what the documents actually say.".freeze

  def default_site_description
    DEFAULT_SITE_DESCRIPTION
  end

  # Public origin for canonicals, Open Graph, and JSON-LD. A request that
  # reaches Puma on a subdomain or the raw IP must not publish that host.
  def public_site_origin
    "https://#{WwwRedirect::APEX_HOST}"
  end

  # Canonical URL for the current path. Query strings (fbclid, utm_*, page)
  # are not part of request.path, and a trailing slash is stripped except on /.
  def canonical_page_url
    path = request.path.to_s
    path = "/" if path.blank? || path == "/"
    path = path.chomp("/") unless path == "/"
    "#{public_site_origin}#{path}"
  end

  def paywall_structured_data
    return unless site_gated? && crawler_readable_page?

    data = {
      "@context" => "https://schema.org",
      "@type" => "WebPage",
      "url" => canonical_page_url,
      "isAccessibleForFree" => false
    }
    # Only these detail templates render a full reporting section with this
    # selector. Index pages keep their page-level paywall declaration.
    if controller.action_name == "show" && %w[topics meetings committees members].include?(controller.controller_path)
      data["hasPart"] = {
        "@type" => "WebPageElement",
        "isAccessibleForFree" => false,
        "cssSelector" => ".gated-content"
      }
    end
    data
  end

  # Publisher facts the app already publishes: the site name, this request's
  # origin, the favicon, and the default description. No founder, place, or
  # contact fields — those are not stored.
  def organization_structured_data
    {
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "name" => "Two Rivers Matters",
      "url" => "#{public_site_origin}/",
      "logo" => "#{public_site_origin}/icon.png",
      "description" => default_site_description
    }
  end

  # Wraps member/crawler full content when the site is gated, so the paywall
  # cssSelector has a target. Open mode returns the block unchanged.
  def gated_content(&block)
    captured = capture(&block)
    return captured unless site_gated?

    tag.div(class: "gated-content") { captured }
  end

  # Renders as much of `text` as an anonymous visitor is allowed to see.
  #
  # The withheld remainder is never placed in the response — the fade is a
  # visual disguise for the truncation point, not a concealment mechanism.
  #
  # fade: :block  — vertical gradient, for multi-line prose
  # fade: :inline — horizontal gradient, for single-line card headlines
  def teaser(text, chars:, fade: :block)
    return nil if text.blank?
    return text unless gated_for_visitor?

    # Force a plain String before truncating: when no truncation actually
    # fires, String#truncate returns `dup` of the input, and `dup` on an
    # ActiveSupport::SafeBuffer preserves html_safe — which would make
    # tag.span skip escaping. String.new(...) strips that flag.
    visible = String.new(text.to_s).truncate(chars, separator: " ", omission: "")
    modifier = fade == :inline ? " teaser-fade--inline" : ""

    tag.span(visible, class: "teaser-fade#{modifier}")
  end
end
