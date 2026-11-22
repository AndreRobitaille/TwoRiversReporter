module Topics
  # Called before the source transaction commits, after all page/attachment
  # changes. Topic locks serialize this check with publication and topic merges.
  class WithdrawSourceBriefings
    def self.call(document_id:, meeting_id:)
      ActiveRecord::Base.uncached do
        observations = CouncilDecisionObservation.joins(:minutes_extraction)
          .where("minutes_extractions.input_manifest @> ?::jsonb", { source: { document_id: document_id } }.to_json)
        receipt = { source_catalog: [ { document_id: document_id } ] }
        affected = TopicBriefing.where("generation_data @> ?::jsonb", receipt.to_json)
        observations.pluck(:id).each do |id|
          receipt = { evidence_manifest: { motion_evidence: [ { reference: { observation_id: id } } ] } }
          affected = affected.or(TopicBriefing.where("generation_data @> ?::jsonb", receipt.to_json))
        end

        # Protect first publication too, when there is no stored receipt yet.
        owners = AgendaItemTopic.where(agenda_item_id: AgendaItem.where(meeting_id: meeting_id).select(:id)).select(:topic_id)
        summaries = TopicSummary.where(meeting_id: meeting_id).select(:topic_id)
        events = TopicStatusEvent.where(decision_observation_id: observations.select(:id)).select(:topic_id)
        locked_ids = []
        loop do
          candidates = Topic.where(id: affected.select(:topic_id)).or(Topic.where(id: owners))
            .or(Topic.where(id: summaries)).or(Topic.where(id: events))
          missing = candidates.where.not(id: locked_ids).pluck(:id)
          break if missing.empty?
          locked_ids.concat(Topic.where(id: missing).order(:id).lock.pluck(:id))
        end

        affected.published.find_each do |briefing|
          data = briefing.generation_data
          sources = data["source_catalog"]
          motions = data.dig("evidence_manifest", "motion_evidence")
          next if GenerationEvidence.sources_current?(sources) &&
            (motions.nil? || GenerationEvidence.motion_evidence_current?(briefing.topic_id, motions))

          document = MeetingDocument.find_by(id: document_id)
          AuditEvent.record!(actor: nil, action: "topic_briefing.source_withdrawn", subject: briefing, label: "Topic: #{briefing.topic.name}",
            metadata: { actor_type: "system", method: "document_dependencies_v1", document_id: document_id,
              reason: document ? "source_changed" : "source_unavailable",
              source_catalog: sources, evidence_manifest: data["evidence_manifest"],
              current_source: document && Citations::SourceCatalog.snapshot(document) })
          briefing.update!(evidence_withdrawn_at: Time.current, withdrawal_correction: nil)
          GeneratedImage.where(source_briefing_id: briefing.id, status: %w[pending processing ready failed])
            .update_all(status: "superseded", failure_reason: "Supporting briefing withdrawn", updated_at: Time.current)
        end
      end
    end
  end
end
