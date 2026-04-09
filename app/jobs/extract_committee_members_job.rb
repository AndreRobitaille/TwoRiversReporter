class ExtractCommitteeMembersJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    minutes_doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf")

    unless minutes_doc&.extracted_text.present?
      Rails.logger.info "No minutes text available for Meeting #{meeting_id}"
      return
    end

    ai_service = ::Ai::OpenAiService.new
    json_response = ai_service.extract_committee_members(minutes_doc.extracted_text, source: meeting)

    begin
      data = JSON.parse(json_response)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse committee members JSON for Meeting #{meeting_id}: #{e.message}"
      return
    end

    meeting.meeting_attendances.destroy_all
    create_attendance_records(meeting, data)

    reconcile_memberships(meeting) if meeting.committee_id.present?
    detect_departures(meeting) if meeting.committee_id.present?

    Rails.logger.info "Extracted #{meeting.meeting_attendances.count} attendees for Meeting #{meeting_id}"
  end

  private

  def create_attendance_records(meeting, data)
    (data["voting_members_present"] || []).each do |name|
      next if name.blank?

      member = Member.resolve(name)
      next unless member
      next if meeting.meeting_attendances.exists?(member: member)

      meeting.meeting_attendances.create!(
        member: member, status: "present", attendee_type: "voting_member"
      )
    end

    (data["voting_members_absent"] || []).each do |name|
      next if name.blank?

      member = Member.resolve(name)
      next unless member
      next if meeting.meeting_attendances.exists?(member: member)

      meeting.meeting_attendances.create!(
        member: member, status: "absent", attendee_type: "voting_member"
      )
    end

    (data["non_voting_staff"] || []).each do |entry|
      name = entry.is_a?(Hash) ? entry["name"] : entry
      next if name.blank?

      member = Member.resolve(name)
      next unless member
      next if meeting.meeting_attendances.exists?(member: member)

      meeting.meeting_attendances.create!(
        member: member, status: "present", attendee_type: "non_voting_staff",
        capacity: entry.is_a?(Hash) ? entry["capacity"] : nil
      )
    end

    (data["guests"] || []).each do |entry|
      name = entry.is_a?(Hash) ? entry["name"] : entry
      next if name.blank?

      member = Member.resolve(name)
      next unless member
      next if meeting.meeting_attendances.exists?(member: member)

      meeting.meeting_attendances.create!(
        member: member, status: "present", attendee_type: "guest"
      )
    end
  end

  def reconcile_memberships(meeting)
    committee = meeting.committee

    meeting.meeting_attendances.where(attendee_type: %w[voting_member non_voting_staff]).find_each do |attendance|
      next if CommitteeMembership.current.exists?(committee: committee, member_id: attendance.member_id)

      role = attendance.attendee_type == "voting_member" ? "member" : "staff"

      CommitteeMembership.create!(
        committee: committee,
        member_id: attendance.member_id,
        role: role,
        source: "ai_extracted",
        started_on: meeting.starts_at.to_date
      )
    end
  end

  def detect_departures(meeting)
    committee = meeting.committee

    meetings_with_attendance = Meeting
      .where(committee: committee)
      .where("meetings.starts_at <= ?", meeting.starts_at)
      .where(id: MeetingAttendance.select(:meeting_id))
      .order(starts_at: :desc)
      .limit(2)

    recent_meeting_ids = meetings_with_attendance.pluck(:id)

    return if recent_meeting_ids.size < 2

    active_memberships = CommitteeMembership
      .current
      .where(committee: committee, source: "ai_extracted")

    active_memberships.find_each do |membership|
      appears_in_recent = MeetingAttendance
        .where(meeting_id: recent_meeting_ids, member_id: membership.member_id)
        .exists?

      next if appears_in_recent

      last_attendance = MeetingAttendance
        .joins(:meeting)
        .where(member_id: membership.member_id)
        .where(meetings: { committee_id: committee.id })
        .order("meetings.starts_at DESC")
        .first

      ended_date = last_attendance&.meeting&.starts_at&.to_date || meeting.starts_at.to_date
      membership.update!(ended_on: ended_date)
    end
  end
end
