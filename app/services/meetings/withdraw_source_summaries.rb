module Meetings
  # Runs under SummaryPublication's lock in the source writer's transaction.
  # Legacy summaries without a source catalog remain explicitly unverified.
  class WithdrawSourceSummaries
    def self.call(document_id:)
      receipt = { source_catalog: [ { document_id: document_id } ] }
      MeetingSummary.published.where("generation_data @> ?::jsonb", receipt.to_json).order(:id).lock.each do |summary|
        sources = summary.generation_data.fetch("source_catalog")
        next if Topics::GenerationEvidence.sources_current?(sources)

        document = MeetingDocument.find_by(id: document_id)
        AuditEvent.record!(actor: nil, action: "meeting_summary.source_withdrawn", subject: summary,
          label: "Meeting: #{summary.meeting.body_name} (#{summary.meeting_id})", metadata: {
            actor_type: "system", method: "document_dependencies_v1", document_id: document_id,
            reason: document ? "source_changed" : "source_unavailable", source_catalog: sources,
            current_source: document && Citations::SourceCatalog.snapshot(document)
          })
        summary.update!(evidence_withdrawn_at: Time.current)
        GeneratedImage.where(source_summary_id: summary.id, status: %w[pending processing ready failed])
          .update_all(status: "superseded", failure_reason: "Supporting summary withdrawn", updated_at: Time.current)
      end
    end
  end
end
