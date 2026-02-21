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

  def signal_badge(type)
    css_class = "badge--default"
    label = case type
    when "deferral_signal" then "Deferral Observed"
    when "disappearance_signal" then "Disappearance Observed"
    when "cross_body_progression" then "Body Change"
    when "rules_engine_update" then "Status Update"
    else type.humanize
    end
    tag.span(label, class: "badge #{css_class} badge--outline", title: type.humanize)
  end

  # Maps a TopicStatusEvent to a short highlight label for the topics index.
  # Returns nil if the event type is not highlight-worthy.
  HIGHLIGHT_LABELS = {
    "agenda_recurrence" => "Resurfaced",
    "deferral_signal" => "Deferral Observed",
    "cross_body_progression" => "Moved Bodies",
    "disappearance_signal" => "Disappeared"
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
