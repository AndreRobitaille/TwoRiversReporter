module ApplicationHelper
  include Pagy::Frontend

  def markdown(text)
    return "" if text.blank?

    # Simple markdown using Kramdown as previously configured
    sanitize Kramdown::Document.new(text).to_html
  end

  # Sanitize external URLs to prevent javascript: and other dangerous schemes
  def safe_external_url(url)
    return "#" if url.blank?

    uri = URI.parse(url)
    uri.scheme&.match?(/\Ahttps?\z/i) ? url : "#"
  rescue URI::InvalidURIError
    "#"
  end
end
