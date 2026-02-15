module ApplicationHelper
  def markdown(text)
    return "" if text.blank?

    # Simple markdown using Kramdown as previously configured
    Kramdown::Document.new(text).to_html.html_safe
  end
end
