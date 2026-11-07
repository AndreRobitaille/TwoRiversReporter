module Topics
  # Runs inside identity review's transaction, under the same topic locks used
  # by generation and topic merges. No provider calls or regeneration dispatch.
  class WithdrawCorrectedBriefings
    def self.call(observation_ids:, correction:)
      affected = TopicBriefing.none
      observation_ids.uniq.each do |id|
        receipt = { evidence_manifest: { motion_evidence: [ { reference: { observation_id: id } } ] } }
        affected = affected.or(TopicBriefing.where("generation_data @> ?::jsonb", receipt.to_json))
      end
      event_topics = TopicStatusEvent.where(decision_observation_id: observation_ids).select(:topic_id)
      locked_ids = []
      loop do
        # Include event owners even before their first briefing is saved. Recheck
        # after locking so a completed topic merge cannot move a receipt away.
        candidates = Topic.where(id: affected.select(:topic_id)).or(Topic.where(id: event_topics))
        missing = candidates.where.not(id: locked_ids).pluck(:id)
        break if missing.empty?
        locked_ids.concat(Topic.where(id: missing).order(:id).lock.pluck(:id))
      end

      affected.published.find_each do |briefing|
        events = briefing.generation_data.dig("evidence_manifest", "motion_evidence")
        next if GenerationEvidence.motion_evidence_current?(briefing.topic_id, events)

        briefing.update!(evidence_withdrawn_at: Time.current, withdrawal_correction: correction)
        GeneratedImage.where(source_briefing_id: briefing.id, status: %w[pending processing ready failed])
          .update_all(status: "superseded", failure_reason: "Supporting briefing withdrawn", updated_at: Time.current)
      end
    end
  end
end
