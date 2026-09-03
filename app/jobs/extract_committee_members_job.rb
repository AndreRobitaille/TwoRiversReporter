class ExtractCommitteeMembersJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    minutes_doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf")

    unless minutes_doc&.extracted_text.present?
      Rails.logger.info "No minutes text available for Meeting #{meeting_id}"
      stamp_processing_state(meeting, "missing_source")
      return
    end

    ai_service = ::Ai::OpenAiService.new
    json_response = ai_service.extract_committee_members(minutes_doc.extracted_text, source: meeting)

    begin
      data = JSON.parse(json_response)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse committee members JSON for Meeting #{meeting_id}: #{e.message}"
      stamp_processing_state(meeting, "parse_error")
      return
    end

    created_any = false
    ActiveRecord::Base.transaction do
      meeting.meeting_attendances.destroy_all
      created_any = create_attendance_records(meeting, data)

      Committees::MembershipReconciler.call(meeting.committee) if meeting.committee_id.present?
    end

    Rails.logger.info "Extracted #{meeting.meeting_attendances.count} attendees for Meeting #{meeting_id}"
    stamp_processing_state(meeting, created_any ? "processed" : "empty")
  end

  private

  def create_attendance_records(meeting, data)
    created = false
    (data["voting_members_present"] || []).each do |name|
      next if name.blank?

      member = Member.resolve(name)
      next unless member
      next if meeting.meeting_attendances.exists?(member: member)

      meeting.meeting_attendances.create!(
        member: member, status: "present", attendee_type: "voting_member"
      )
      created = true
    end

    (data["voting_members_absent"] || []).each do |name|
      next if name.blank?

      member = Member.resolve(name)
      next unless member
      next if meeting.meeting_attendances.exists?(member: member)

      meeting.meeting_attendances.create!(
        member: member, status: "absent", attendee_type: "voting_member"
      )
      created = true
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
      created = true
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
      created = true
    end

    created
  end

  def stamp_processing_state(meeting, status)
    meeting.mark_processing!("committee_members_extracted_at")
    meeting.with_lock do
      meeting.update!(processing_state: meeting.processing_state.merge("committee_members_extraction_status" => status))
    end
  end
end
