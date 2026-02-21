module TopicsHelper
  def topic_lifecycle_badge(status)
    css_class = case status
    when "active" then "badge--success"
    when "resolved" then "badge--info"
    when "recurring" then "badge--warning"
    when "dormant" then "badge--secondary"
    else "badge--default"
    end
    tag.span(status.humanize, class: "badge #{css_class}")
  end

  # Maps a TopicStatusEvent to a short highlight label for the topics index.
  # Returns nil if the event type is not highlight-worthy.
  HIGHLIGHT_LABELS = {
    "agenda_recurrence" => "Resurfaced",
    "deferral_signal" => "Delayed",
    "cross_body_progression" => "Moved to new committee",
    "disappearance_signal" => "No longer on agenda"
  }.freeze

  def highlight_signal_label(evidence_type, lifecycle_status = nil)
    return "Newly Active" if evidence_type == "rules_engine_update" && lifecycle_status == "active"

    HIGHLIGHT_LABELS[evidence_type]
  end

  def group_last_activity_label(last_activity_at)
    return "Not yet recorded" if last_activity_at.blank?

    "#{time_ago_in_words(last_activity_at)} ago"
  end

  def motion_outcome_text(motion)
    return motion.outcome if motion.votes.empty?

    yes_count = motion.votes.count { |v| v.value == "yes" }
    no_count = motion.votes.count { |v| v.value == "no" }
    "#{motion.outcome} #{yes_count}-#{no_count}"
  end

  def public_comment_meeting?(agenda_item)
    return false if agenda_item.title.blank?

    agenda_item.title.match?(/public (hearing|comment)/i)
  end

  def render_briefing_editorial(markdown_content)
    return "" if markdown_content.blank?

    paragraphs = markdown_content.split(/\n{2,}/).map(&:strip).reject(&:blank?)
    safe_join(paragraphs.map { |p| content_tag(:p, render_inline_markdown(p)) })
  end

  def render_briefing_record(markdown_content)
    return "" if markdown_content.blank?

    # Handle AI returning a JSON array instead of markdown bullets
    lines = if markdown_content.strip.start_with?("[")
      parsed = JSON.parse(markdown_content) rescue nil
      parsed.is_a?(Array) ? parsed : markdown_content.lines.map(&:chomp)
    else
      markdown_content.lines.map(&:chomp)
    end

    items = lines.filter_map do |line|
      text = line.to_s.sub(/\A\s*[-*]\s*/, "").strip
      next if text.empty?
      content_tag(:li, text)
    end

    return "" if items.empty?
    content_tag(:ul, safe_join(items), class: "topic-record-list")
  end

  # Convert **bold** markdown to <strong> tags
  def render_inline_markdown(text)
    escaped = ERB::Util.html_escape(text)
    bolded = escaped.gsub(/\*\*(.+?)\*\*/) { content_tag(:strong, Regexp.last_match(1)) }
    bolded.html_safe
  end

  def briefing_freshness_badge(briefing)
    return unless briefing.updated_at > 7.days.ago

    label = briefing.created_at == briefing.updated_at ? "New" : "Updated"
    tag.span(label, class: "badge badge--primary")
  end

  def render_topic_summary_content(markdown_content)
    return "" if markdown_content.blank?

    lines = markdown_content.lines.map(&:chomp)

    # Remove heading lines and internal section headers
    filtered = lines.reject do |line|
      line.match?(/\A##\s/) ||
        line.match?(/\A\*\*(Factual Record|Institutional Framing|Civic Sentiment|Continuity|Resident-reported)/i) ||
        line.strip.empty?
    end

    # Convert markdown bullets to HTML list items
    items = filtered.map do |line|
      text = line.sub(/\A\s*[-*]\s*/, "").strip
      next if text.empty?
      content_tag(:li, text)
    end.compact

    return "" if items.empty?
    content_tag(:ul, items.join.html_safe, class: "topic-summary-list")
  end
end
