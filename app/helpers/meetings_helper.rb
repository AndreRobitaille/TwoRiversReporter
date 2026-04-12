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
end
