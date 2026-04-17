module MeetingsHelper
  MEETING_BUFFER = 3.hours

  def meeting_status_badge(meeting)
    return [] unless meeting.starts_at

    upcoming = meeting.starts_at > Time.current - MEETING_BUFFER
    badges = []

    if upcoming
      case meeting.document_status
      when :agenda
        badges << tag.span("Agenda posted", class: "badge badge--info")
      when :packet
        badges << tag.span("Documents available", class: "badge badge--info")
      end
    else
      if meeting.document_status == :minutes
        badges << tag.span("Minutes available", class: "badge badge--success")
      else
        badges << tag.span("Awaiting minutes", class: "badge badge--warning")
      end
    end

    if meeting.meeting_summaries.any?
      badges << tag.span("Summary", class: "badge badge--success")
    end

    return nil if badges.empty?
    safe_join(badges, " ")
  end

  # --- generation_data extraction helpers ---

  def meeting_headline(generation_data)
    return nil if generation_data.blank?
    generation_data["headline"]
  end

  def meeting_highlights(generation_data)
    return [] if generation_data.blank?
    generation_data["highlights"] || []
  end

  def meeting_public_input(generation_data)
    return [] if generation_data.blank?
    generation_data["public_input"] || []
  end

  def meeting_item_details(generation_data)
    return [] if generation_data.blank?
    generation_data["item_details"] || []
  end

  def decision_badge_class(decision)
    case decision&.downcase
    when "passed" then "decision-badge--passed"
    when "failed" then "decision-badge--failed"
    when "tabled", "referred" then "decision-badge--tabled"
    else "decision-badge--default"
    end
  end

  PRODUCTION_HOST = "tworiversmatters.com".freeze

  def share_text(meeting, summary)
    lines = []

    name = meeting.body_name.sub(/ Meeting$/, "")
    upcoming = meeting.starts_at.present? && meeting.starts_at > Time.current

    # Temporal header + date/time (no blank line between)
    lines << share_text_temporal_header(meeting, name, upcoming)
    lines << meeting.starts_at&.strftime("%B %-d, %Y — %-l:%M %p")
    lines << ""

    gd = summary&.generation_data
    meeting_url = "https://#{PRODUCTION_HOST}/meetings/#{meeting.id}"

    if gd.present?
      headline = gd["headline"]
      lines << headline if headline.present?
      lines << "" if headline.present?

      if upcoming
        share_text_upcoming_bullets(lines, gd)
      else
        share_text_past_bullets(lines, gd)
      end
    elsif meeting.respond_to?(:agenda_items) && meeting.agenda_items.any?
      share_text_agenda_fallback(lines, meeting)
    end

    lines << "" unless lines.last == ""
    lines << "Full details at Two Rivers Matters:"
    lines << meeting_url

    lines.join("\n")
  end

  def share_og_description(summary)
    headline = summary&.generation_data&.dig("headline")
    return "Meeting details and AI-generated summary." if headline.blank?
    return headline if headline.length <= 200

    headline[0..196] + "..."
  end

  PROCEDURAL_TITLE_PATTERN = /\A\s*(call to order|roll call|adjourn|recess|reconvene|pledge of allegiance|approval of .*minutes|treasurer'?s? report|consent agenda)/i

  SUMMARY_TYPE_PRIORITY = %w[minutes_recap transcript_recap packet_analysis agenda_preview].freeze

  def meeting_share_description(meeting)
    summary = preferred_meeting_summary(meeting)
    headline = summary&.generation_data&.dig("headline")
    return headline if headline.present?

    items = substantive_agenda_items(meeting)
    return agenda_fallback_description(meeting, items) if items.any?

    bare_meeting_description(meeting)
  end

  COUNCIL_PATTERNS = [
    "City Council Meeting",
    "City Council Work Session",
    "City Council Special Meeting"
  ].freeze

  def council_meeting?(meeting)
    meeting.body_name.in?(COUNCIL_PATTERNS) ||
      (meeting.body_name.include?("Council") && !meeting.body_name.include?("Work Session"))
  end

  def best_headline(meeting)
    summary = meeting.meeting_summaries.find { |s| s.summary_type == "minutes_recap" } ||
              meeting.meeting_summaries.find { |s| s.summary_type == "transcript_recap" } ||
              meeting.meeting_summaries.find { |s| s.summary_type == "packet_analysis" }
    return nil unless summary
    meeting_headline(summary.generation_data)
  end

  private

  def preferred_meeting_summary(meeting)
    meeting.meeting_summaries
      .to_a
      .min_by { |s| SUMMARY_TYPE_PRIORITY.index(s.summary_type) || 99 }
  end

  def substantive_agenda_items(meeting)
    meeting.agenda_items.reject { |i| i.title.to_s.match?(PROCEDURAL_TITLE_PATTERN) }
  end

  def agenda_fallback_description(meeting, items)
    body = cleaned_meeting_body_name(meeting)
    date = formatted_meeting_date(meeting)
    truncated = items.map { |i| truncate(i.title.to_s, length: 40, omission: "...") }

    if items.count <= 4
      "Two Rivers #{body}, #{date} — #{truncated.to_sentence(two_words_connector: ', ')}."
    else
      first_three = truncated.first(3)
      remaining = items.count - 3
      noun = remaining == 1 ? "item" : "items"
      "Two Rivers #{body}, #{date} — #{first_three.join(', ')}, and #{remaining} other #{noun} on the agenda."
    end
  end

  def bare_meeting_description(meeting)
    "Two Rivers #{cleaned_meeting_body_name(meeting)} — #{formatted_meeting_date(meeting)}."
  end

  def cleaned_meeting_body_name(meeting)
    meeting.body_name.to_s.sub(/ Meeting\z/i, "").strip
  end

  def formatted_meeting_date(meeting)
    meeting.starts_at&.strftime("%B %-d, %Y") || "date TBD"
  end

  def share_text_temporal_header(meeting, name, upcoming)
    if upcoming
      days_until = (meeting.starts_at.to_date - Date.current).to_i
      prefix = case days_until
      when 0 then "At tonight's"
      when 1 then "At tomorrow's"
      else "At the upcoming"
      end
      "#{prefix} #{name} meeting:"
    else
      days_ago = (Date.current - meeting.starts_at.to_date).to_i
      prefix = case days_ago
      when 0 then "At today's"
      when 1 then "At yesterday's"
      else "At last #{meeting.starts_at.strftime("%A")}'s" if days_ago < 7
      end
      if prefix
        "#{prefix} #{name} meeting:"
      else
        "#{name}:"
      end
    end
  end

  def share_text_past_bullets(lines, gd)
    highlights = gd["highlights"] || []
    return if highlights.empty?

    lines << "Key decisions:"
    lines << ""
    highlights.first(5).each_with_index do |h, i|
      bullet = "* #{h["text"]}"
      bullet += " (#{h["vote"]})" if h["vote"].present?
      lines << bullet
      lines << "" if i < [ highlights.size, 5 ].min - 1
    end
  end

  def share_text_upcoming_bullets(lines, gd)
    highlights = gd["highlights"] || []
    items = gd["item_details"] || []

    # Prefer highlights (plain-language summaries) over raw agenda titles
    bullets = if highlights.any?
      highlights.first(5).map { |h| h["text"] }
    elsif items.any?
      items.first(5).map { |i| i["agenda_item_title"] }
    end

    return if bullets.blank?

    lines << "On the agenda:"
    lines << ""
    bullets.each_with_index do |b, i|
      lines << "* #{b}"
      lines << "" if i < bullets.size - 1
    end
  end

  def share_text_agenda_fallback(lines, meeting)
    items = meeting.agenda_items
      .reject { |ai| ai.title&.match?(/\A(CALL TO ORDER|ROLL CALL|ADJOURNMENT|PUBLIC INPUT)\z/i) }
    return if items.empty?

    lines << "On the agenda:"
    lines << ""
    items.first(5).each_with_index do |ai, i|
      lines << "* #{ai.title}"
      lines << "" if i < [ items.size, 5 ].min - 1
    end
  end
end
