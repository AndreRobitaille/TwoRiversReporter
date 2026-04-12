module CommitteesHelper
  ROLE_SORT_ORDER = { "chair" => 0, "vice_chair" => 1 }.freeze
  COMMITTEE_TYPE_DISPLAY = {
    "city" => "City Government",
    "tax_funded_nonprofit" => "Tax-Funded Nonprofit",
    "external" => "Other Organization"
  }.freeze

  def committee_type_label(committee_type)
    COMMITTEE_TYPE_DISPLAY[committee_type] || committee_type.titleize
  end

  # Sort memberships: chair first, vice chair second, council members third, then alphabetical.
  def sort_memberships(memberships, council_member_ids)
    memberships.sort_by do |cm|
      role_order = ROLE_SORT_ORDER[cm.role] || (council_member_ids.include?(cm.member_id) ? 2 : 3)
      [ role_order, cm.member.name.split.last.downcase ]
    end
  end

  # Render committee description with safe markdown link support.
  # Converts markdown-style links [text](url) to HTML <a> tags.
  # Only allows http/https URLs. All other content is HTML-escaped.
  def render_committee_description(text)
    return "" if text.blank?

    escaped = ERB::Util.html_escape(text)
    # Convert markdown links: [text](url) → <a href="url">text</a>
    with_links = escaped.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do
      link_text = Regexp.last_match(1)
      url = CGI.unescapeHTML(Regexp.last_match(2))
      if url.match?(%r{\Ahttps?://})
        "<a href=\"#{ERB::Util.html_escape(url)}\" target=\"_blank\" rel=\"noopener\">#{link_text}</a>"
      else
        link_text
      end
    end
    simple_format(with_links, {}, sanitize: false)
  end
end
