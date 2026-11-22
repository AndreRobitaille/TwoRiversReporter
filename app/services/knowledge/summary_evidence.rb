require "digest"

module Knowledge
  # A dependency receipt, not factual approval. Keep the original summary ID
  # and payload digest even after ordinary summary deletion nullifies its FK.
  class SummaryEvidence
    def self.capture(summary)
      return unless summary.published?

      { "version" => 1, "summary_id" => summary.id, "meeting_id" => summary.meeting_id,
        "summary_type" => summary.summary_type,
        "payload_sha256" => Digest::SHA256.hexdigest(JSON.generate(canonical([ summary.content, summary.generation_data ]))) }
    end

    def self.withdraw_dependents(summary, removed: false)
      current = capture(summary) unless removed
      KnowledgeSource.available.where(source_summary_id: summary.id).order(:id).lock("FOR NO KEY UPDATE").each do |source|
        next if source.source_summary_manifest == current

        AuditEvent.record!(actor: nil, action: "knowledge_source.evidence_withdrawn", subject: source,
          label: "Knowledge: #{source.title}", metadata: {
            actor_type: "system", method: "knowledge_summary_v1",
            reason: removed ? "summary_removed" : "summary_changed_or_withdrawn",
            source_summary_manifest: source.source_summary_manifest, current_summary_manifest: current
          })
        source.update!(evidence_withdrawn_at: Time.current)
      end
    end

    def self.canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end
    private_class_method :canonical
  end
end
