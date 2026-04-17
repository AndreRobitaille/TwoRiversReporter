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

  # Convert **bold** markdown to <strong> tags
  def render_inline_markdown(text)
    escaped = ERB::Util.html_escape(text)
    bolded = escaped.gsub(/\*\*(.+?)\*\*/) { content_tag(:strong, Regexp.last_match(1).html_safe) }
    bolded.html_safe
  end

  def briefing_freshness_badge(briefing)
    return unless briefing.updated_at > 7.days.ago

    label = briefing.created_at == briefing.updated_at ? "New" : "Updated"
    tag.span(label, class: "badge badge--primary")
  end

  def briefing_what_to_watch(briefing)
    briefing&.generation_data&.dig("editorial_analysis", "what_to_watch")
  end

  def briefing_current_state(briefing)
    briefing&.generation_data&.dig("editorial_analysis", "current_state") ||
      briefing&.editorial_content
  end

  def briefing_process_concerns(briefing)
    value = briefing&.generation_data&.dig("editorial_analysis", "process_concerns")
    case value
    when Array then value
    when String then [ value ]
    else []
    end
  end

  def briefing_factual_record(briefing)
    briefing&.generation_data&.dig("factual_record") || []
  end

  def format_record_date(date_string)
    Date.parse(date_string).strftime("%b %-d, %Y")
  rescue Date::Error, TypeError
    date_string.to_s
  end

  # Clean a meeting name for display. Strips trailing " Meeting", parenthetical
  # status suffixes, date suffixes the AI sometimes appends, and " - NO QUORUM".
  # Safe to call with either canonical Meeting.body_name values or raw AI text.
  def clean_meeting_display(name)
    return "" if name.blank?
    name.to_s
        .gsub(/\s*\([^)]*\)\s*\z/, "")    # strip trailing "(CANCELED - NO QUORUM)"
        .gsub(/,\s*[A-Z][a-z]{2,}\s+\d{1,2}(?:,?\s+\d{4})?\z/, "")  # strip ", Nov 20 2025"
        .sub(/\s+Meeting\z/, "")          # strip trailing " Meeting"
        .sub(/\s+-\s+NO QUORUM.*\z/i, "") # strip trailing " - NO QUORUM"
        .strip
  end

  def enrich_record_entry(entry, record_meetings)
    candidates = record_meetings[entry["date"]] || []
    target_norm = normalize_meeting_name(entry["meeting"])
    appearance = candidates.find { |a| normalize_meeting_name(a.meeting.body_name) == target_norm }
    meeting = appearance&.meeting

    event_text = entry["event"]
    if event_text&.match?(/appeared on the agenda/i) && appearance
      enriched = extract_meeting_item_summary(meeting, appearance.agenda_item)
      event_text = enriched if enriched.present?
    end

    # Prefer the canonical Meeting body_name (cleaned) when we have a match,
    # so display is consistent regardless of how the AI labeled the entry.
    # Falls back to cleaning the AI's text when there's no matched Meeting.
    display_name = if meeting
      clean_meeting_display(meeting.body_name)
    else
      clean_meeting_display(entry["meeting"])
    end

    { event: event_text, meeting_name: display_name, meeting: meeting }
  end

  def topic_share_description(topic)
    headline = topic.topic_briefing&.headline
    return headline if headline.present?

    name_sentence = topic.name.to_s.downcase.sub(/\A[a-z]/, &:upcase)
    "#{name_sentence} in Two Rivers, WI — every city meeting where it's come up, every vote, and what's still unresolved."
  end

  private

  # Normalize meeting name strings for MATCHING between AI-generated
  # factual_record "meeting" labels and real Meeting body_name values.
  # Returns a word-set representation — use clean_meeting_display for
  # human-readable output.
  def normalize_meeting_name(name)
    name.to_s.downcase
        .gsub(/\([^)]*\)/, "")            # strip parentheticals: (CANCELED...)
        .gsub(/,.*\z/, "")                # strip trailing ", Nov 20 2025"
        .strip
        .sub(/\s+-\s+no quorum.*\z/, "")  # strip trailing " - NO QUORUM"
        .sub(/\s+meeting\z/, "")          # strip trailing " meeting"
        .gsub(/[^a-z0-9]+/, " ")
        .split.sort.join(" ")
  end

  # Attempts to replace a generic "appeared on the agenda" Record entry with
  # real content, in this order:
  #   1. Matching item_details.summary from the meeting's MeetingSummary
  #   2. The agenda_item title as a cleaner fallback
  #   3. nil — let the caller keep the original event text
  #
  # TopicAppearance.agenda_item is optional (some appearances are linked to
  # meetings without a specific agenda item). When agenda_item is nil we can't
  # identify which item summary to pull, so we fall through the summary loop
  # and return nil at the end. The caller's `if enriched.present?` guard then
  # preserves the original event text instead of replacing it with nothing.
  def extract_meeting_item_summary(meeting, agenda_item)
    return agenda_item&.title unless meeting

    meeting.meeting_summaries.each do |summary|
      items = summary.generation_data&.dig("item_details")
      next unless items.is_a?(Array)

      target_title = agenda_item&.title&.downcase
      next unless target_title

      matched_item = items.find { |item|
        item_title = item["agenda_item_title"]&.downcase
        next false unless item_title
        item_title.include?(target_title) || target_title.include?(item_title)
      }

      return matched_item["summary"].truncate(200) if matched_item&.dig("summary").present?
    end

    agenda_item&.title
  end
end
