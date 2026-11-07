module Topics
  # Runs inside fact publication, after the new projection becomes visible to
  # this transaction. No generation or provider work is dispatched here.
  class WithdrawFactBriefings
    def self.call(meeting:, previous_publication:, publication:, previous_motion_ids:)
      ActiveRecord::Base.uncached do
        observations = CouncilDecisionObservation.joins(:minutes_extraction)
          .where(minutes_extractions: { original_meeting_id: meeting.id })
        legacy_events = TopicStatusEvent.where(evidence_type: "motion_outcome", decision_observation_id: nil)
          .where("source_ref->>'motion_id' IN (?)", previous_motion_ids.map(&:to_s))
        events = TopicStatusEvent.where(decision_observation_id: observations.select(:id)).or(legacy_events)
        owners = AgendaItemTopic.where(agenda_item_id: AgendaItem.where(meeting_id: meeting.id).select(:id)).select(:topic_id)
        locked_ids = []
        affected = TopicBriefing.none
        loop do
          # Recompute after waiting: continuity may have created a first event,
          # or a topic merge may have moved an existing receipt to a new owner.
          affected = affected_briefings(observations, events)
          candidates = Topic.where(id: affected.select(:topic_id)).or(Topic.where(id: owners))
            .or(Topic.where(id: events.select(:topic_id)))
          missing = candidates.where.not(id: locked_ids).pluck(:id)
          break if missing.empty?
          locked_ids.concat(Topic.where(id: missing).order(:id).lock.pluck(:id))
        end

        affected.published.find_each do |briefing|
          manifest = briefing.generation_data.fetch("evidence_manifest")
          next if GenerationEvidence.motion_evidence_current?(briefing.topic_id, manifest["motion_evidence"])

          AuditEvent.record!(actor: nil, action: "topic_briefing.facts_withdrawn", subject: briefing, label: "Topic: #{briefing.topic.name}",
            metadata: { actor_type: "system", method: "fact_publication_dependencies_v1", reason: "motion_evidence_changed", meeting_id: meeting.id,
              previous_publication: snapshot(previous_publication), current_publication: snapshot(publication), evidence_manifest: manifest })
          briefing.update!(evidence_withdrawn_at: Time.current, withdrawal_correction: nil)
          GeneratedImage.where(source_briefing_id: briefing.id, status: %w[pending processing ready failed])
            .update_all(status: "superseded", failure_reason: "Supporting briefing withdrawn", updated_at: Time.current)
        end
      end
    end

    def self.affected_briefings(observations, events)
      references = observations.pluck(:id).map { |id| { reference: { observation_id: id } } }
      references.concat(events.pluck(:id).map { |id| { event_id: id } })
      references.reduce(TopicBriefing.none) do |scope, reference|
        receipt = { evidence_manifest: { motion_evidence: [ reference ] } }
        scope.or(TopicBriefing.where("generation_data @> ?::jsonb", receipt.to_json))
      end
    end
    private_class_method :affected_briefings

    def self.snapshot(publication)
      publication&.attributes&.slice("id", "fingerprint", "votes_extraction_id", "attendance_extraction_id", "projection_context")
    end
    private_class_method :snapshot
  end
end
