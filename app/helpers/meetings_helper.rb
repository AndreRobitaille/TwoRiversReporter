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

    # Header: body name (strip " Meeting" suffix) + date/time
    name = meeting.body_name.sub(/ Meeting$/, "")
    date = meeting.starts_at&.strftime("%B %-d, %Y")
    time = meeting.starts_at&.strftime("%-l:%M %p")
    lines << "#{name} — #{date}, #{time}"
    lines << ""

    gd = summary&.generation_data
    meeting_url = "https://#{PRODUCTION_HOST}/meetings/#{meeting.id}"

    if gd.present?
      # Headline paragraph
      headline = gd["headline"]
      lines << headline if headline.present?
      lines << "" if headline.present?

      upcoming = meeting.starts_at.present? && meeting.starts_at > Time.current

      if upcoming
        share_text_upcoming_bullets(lines, gd)
      else
        share_text_past_bullets(lines, gd)
      end
    elsif meeting.respond_to?(:agenda_items) && meeting.agenda_items.any?
      share_text_agenda_fallback(lines, meeting)
    end

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

  def share_text_past_bullets(lines, gd)
    highlights = gd["highlights"] || []
    return if highlights.empty?

    lines << "Key decisions:"
    highlights.first(5).each do |h|
      bullet = " - #{h["text"]}"
      bullet += " (#{h["vote"]})" if h["vote"].present?
      lines << bullet
    end
    lines << ""
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
    bullets.each { |b| lines << " - #{b}" }
    lines << ""
  end

  def share_text_agenda_fallback(lines, meeting)
    items = meeting.agenda_items
      .reject { |ai| ai.title&.match?(/\A(CALL TO ORDER|ROLL CALL|ADJOURNMENT|PUBLIC INPUT)\z/i) }
    return if items.empty?

    lines << "On the agenda:"
    items.first(5).each do |ai|
      lines << " - #{ai.title}"
    end
    lines << ""
  end
end
