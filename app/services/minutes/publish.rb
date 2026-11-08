require "digest"

module Minutes
  class Publish
    STATUS_KEYS = { "votes" => "votes_extraction_status", "attendance" => "committee_members_extraction_status" }.freeze
    MARKERS = { "votes" => "votes_extracted_at", "attendance" => "committee_members_extracted_at" }.freeze

    def self.context_for(meeting)
      { "meeting_starts_at" => meeting.starts_at&.utc&.iso8601(6),
        "committee_id" => meeting.committee_id, "rules" => "minutes_projection_v3" }
    end

    def self.current?(meeting, input: nil)
      input ||= Input.new(meeting)
      publication = meeting.minutes_publication
      publication && publication.projection_context == context_for(meeting) &&
        input.matches_evidence?(publication.votes_extraction, "votes") &&
        input.matches_evidence?(publication.attendance_extraction, "attendance")
    rescue Input::Unavailable
      false
    end

    def self.fingerprint_for(meeting, votes, attendance)
      Digest::SHA256.hexdigest(JSON.generate([ meeting.id, votes.id, attendance.id, context_for(meeting) ]))
    end

    def self.repair_needed?(meeting, input: nil)
      input ||= Input.new(meeting)
      votes, attendance = input.completed_stage("votes"), input.completed_stage("attendance")
      votes && attendance && meeting.minutes_publication&.fingerprint != fingerprint_for(meeting, votes, attendance)
    rescue Input::Unavailable
      false
    end

    def self.call(meeting)
      published = false
      # Publication can wait for a topic generator that is inserting a briefing
      # for this meeting. Its foreign-key check must be able to take KEY SHARE.
      meeting.with_lock("FOR NO KEY UPDATE") do
        document = meeting.meeting_documents.where(document_type: "minutes_pdf").order(created_at: :desc, id: :desc).first
        return false unless document
        document.with_lock do
          input = Input.new(meeting)
          votes = input.completed_stage("votes")
          attendance = input.completed_stage("attendance")
          return false unless votes && attendance

          fingerprint = fingerprint_for(meeting, votes, attendance)
          return false if meeting.minutes_publication&.fingerprint == fingerprint
          Meetings::SummaryPublication.with_lock(meeting.id) do
            previous_publication = meeting.minutes_publication
            previous_motion_ids = meeting.motions.pluck(:id)
            publication = MinutesPublication.find_by(fingerprint: fingerprint) || MinutesPublication.create!(
              meeting: meeting, original_meeting_id: meeting.id, fingerprint: fingerprint, projection_context: context_for(meeting),
              votes_extraction: votes, attendance_extraction: attendance
            )
            statuses = Projection.new(meeting, input, votes, attendance.data).call
            state = meeting.processing_state.dup
            statuses.each do |kind, status|
              state[MARKERS.fetch(kind)] = true
              state[STATUS_KEYS.fetch(kind)] = status
            end
            meeting.update!(minutes_publication: publication, processing_state: state)
            Topics::WithdrawFactBriefings.call(meeting: meeting, previous_publication: previous_publication,
              publication: publication, previous_motion_ids: previous_motion_ids)
            Meetings::WithdrawFactSummaries.call(meeting: meeting, previous_publication: previous_publication, publication: publication)
            published = true
          end
        end
      end
      Topics::UpdateContinuityJob.perform_later(meeting_id: meeting.id) if published
      MatchCampaignActionsJob.perform_later(meeting.id) if published
      published
    rescue Input::Unavailable
      false
    end
  end
end
