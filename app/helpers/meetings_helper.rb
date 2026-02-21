module MeetingsHelper
  MEETING_BUFFER = 3.hours

  def meeting_status_badge(meeting)
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
end
