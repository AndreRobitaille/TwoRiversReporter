module Meetings
  # Topic locks serialize registration of a first preview with context changes.
  # Do not acquire meeting advisory locks here: source writers acquire those
  # before topics. Summary row locks protect existing payloads and consumers.
  class WithdrawAgendaSummaries
    def self.call(topic_ids:)
      ApplicationRecord.uncached do
        affected = topic_ids.compact.uniq.reduce(MeetingSummary.none) do |scope, id|
          receipt = { topic_context_manifest: { entries: [ { topic_id: id } ] } }
          scope.or(MeetingSummary.where("generation_data @> ?::jsonb", receipt.to_json))
        end
        affected.published.order(:id).lock("FOR NO KEY UPDATE").each do |summary|
          manifest = summary.generation_data.fetch("topic_context_manifest")
          current = Topics::AgendaBriefingContext.current_manifest(manifest)
          next if manifest == current

          AuditEvent.record!(actor: nil, action: "meeting_summary.topic_context_withdrawn", subject: summary,
            label: "Meeting: #{summary.meeting.body_name} (#{summary.meeting_id})", metadata: {
              actor_type: "system", method: "agenda_topic_context_v1", reason: "topic_context_changed",
              topic_context_manifest: manifest, current_topic_context_manifest: current
            })
          summary.update!(evidence_withdrawn_at: Time.current)
          GeneratedImage.where(source_summary_id: summary.id, status: %w[pending processing ready failed])
            .update_all(status: "superseded", failure_reason: "Supporting summary withdrawn", updated_at: Time.current)
        end
      end
    end
  end
end
