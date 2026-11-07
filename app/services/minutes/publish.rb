require "digest"

module Minutes
  class Publish
    STATUS_KEYS = { "votes" => "votes_extraction_status", "attendance" => "committee_members_extraction_status" }.freeze
    MARKERS = { "votes" => "votes_extracted_at", "attendance" => "committee_members_extracted_at" }.freeze

    def self.context_for(meeting)
      { "meeting_starts_at" => meeting.starts_at&.utc&.iso8601(6),
        "committee_id" => meeting.committee_id, "rules" => "minutes_projection_v1" }
    end

    def self.current?(meeting, input: nil)
      input ||= Input.new(meeting)
      publication = meeting.minutes_publication
      publication && publication.projection_context == context_for(meeting) && publication.votes_extraction.input_key == input.key("votes") &&
        publication.attendance_extraction.input_key == input.key("attendance")
    rescue Input::Unavailable
      false
    end

    def self.call(meeting)
      published = false
      meeting.with_lock do
        document = meeting.meeting_documents.where(document_type: "minutes_pdf").order(created_at: :desc, id: :desc).first
        return false unless document
        document.with_lock do
          input = Input.new(meeting)
          return false if current?(meeting, input: input)
          votes = MinutesExtraction.find_by(input_key: input.key("votes"), status: "completed")
          attendance = MinutesExtraction.find_by(input_key: input.key("attendance"), status: "completed")
          return false unless votes && attendance

          fingerprint = Digest::SHA256.hexdigest(JSON.generate([ meeting.id, votes.id, attendance.id, context_for(meeting) ]))
          publication = MinutesPublication.find_by(fingerprint: fingerprint) || MinutesPublication.create!(
            meeting: meeting, original_meeting_id: meeting.id, fingerprint: fingerprint, projection_context: context_for(meeting),
            votes_extraction: votes, attendance_extraction: attendance
          )
          statuses = Projection.new(meeting, input, votes.data, attendance.data).call
          state = meeting.processing_state.dup
          statuses.each do |kind, status|
            state[MARKERS.fetch(kind)] = true
            state[STATUS_KEYS.fetch(kind)] = status
          end
          meeting.update!(minutes_publication: publication, processing_state: state)
          published = true
        end
      end
      Topics::UpdateContinuityJob.perform_later(meeting_id: meeting.id) if published
      published
    rescue Input::Unavailable
      false
    end
  end
end
