module ApplicationHelper
  def markdown(text)
    return "" if text.blank?
    Kramdown::Document.new(text).to_html.html_safe
  end
end
