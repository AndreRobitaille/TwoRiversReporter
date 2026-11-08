module Knowledge
  # Additional document text consumed alongside the saved summary. Legacy
  # unversioned text remains identifiable, without claiming retained provenance.
  class DocumentEvidence
    def self.capture(document)
      return [] unless document&.extracted_text.present?

      [ Citations::SourceCatalog.snapshot(document).merge("text_version_id" => document.current_text_version&.id) ]
    end

    def self.current?(sources)
      return false unless Topics::GenerationEvidence.sources_current?(sources)

      Array(sources).all? do |source|
        document = MeetingDocument.find(source.fetch("document_id"))
        next true unless document.source_versions.exists? || document.latest_text_version_id.present?

        text_version = document.current_text_version
        text_version.present? && source["text_version_id"] == text_version.id &&
          text_version.extracted_text == document.extracted_text &&
          document.file.attached? && document.file.blob.checksum == text_version.meeting_document_version.file.blob.checksum
      end
    end

    # The document writer holds the meeting publication lock. Knowledge
    # registration shares it, including when no dependent row exists yet.
    def self.withdraw_dependents(document_id:)
      KnowledgeSource.available.where("source_catalog @> ?::jsonb", [ { document_id: document_id } ].to_json)
        .order(:id).lock("FOR NO KEY UPDATE").each do |source|
        next if current?(source.source_catalog)

        document = MeetingDocument.find_by(id: document_id)
        AuditEvent.record!(actor: nil, action: "knowledge_source.evidence_withdrawn", subject: source,
          label: "Knowledge: #{source.title}", metadata: {
            actor_type: "system", method: "knowledge_documents_v1", document_id: document_id,
            reason: document ? "source_changed" : "source_unavailable", source_catalog: source.source_catalog,
            current_source: document && Citations::SourceCatalog.snapshot(document)
          })
        source.update!(evidence_withdrawn_at: Time.current)
      end
    end
  end
end
