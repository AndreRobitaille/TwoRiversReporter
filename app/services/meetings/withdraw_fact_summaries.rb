module Meetings
  # Called inside fact publication, under the same advisory lock as summaries.
  class WithdrawFactSummaries
    def self.call(meeting:, previous_publication:, publication:)
      current = MotionContext.new(meeting)
      MeetingSummary.published.where(meeting_id: meeting.id).where("generation_data ? 'motion_context_manifest'")
        .order(:id).lock("FOR NO KEY UPDATE").each do |summary|
        manifest = summary.generation_data.fetch("motion_context_manifest")
        next if manifest.nil? || current.matches?(manifest)

        AuditEvent.record!(actor: nil, action: "meeting_summary.facts_withdrawn", subject: summary,
          label: "Meeting: #{meeting.body_name} (#{meeting.id})", metadata: {
            actor_type: "system", method: "meeting_motion_context_v1", reason: "motion_context_changed",
            motion_context_manifest: manifest, current_motion_context_manifest: current.manifest,
            previous_publication: snapshot(previous_publication), current_publication: snapshot(publication)
          })
        summary.update!(evidence_withdrawn_at: Time.current)
        GeneratedImage.where(source_summary_id: summary.id, status: %w[pending processing ready failed])
          .update_all(status: "superseded", failure_reason: "Supporting summary withdrawn", updated_at: Time.current)
      end
    end

    def self.snapshot(publication)
      publication&.attributes&.slice("id", "fingerprint", "votes_extraction_id", "attendance_extraction_id", "projection_context")
    end
    private_class_method :snapshot
  end
end
