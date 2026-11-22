module CouncilHistory
  # Accepted extractions remain tied to the official file, complete text and
  # agenda shown to the original request. Rebuild page references locally.
  class ReviewedFacts
    def self.export
      MinutesExtraction.where(status: "completed").includes(:meeting, meeting_document_text_version: :meeting_document_version).filter_map do |stage|
        version = stage.meeting_document_text_version&.meeting_document_version
        next unless version && stage.meeting && stage.source_text == stage.meeting_document_text_version.extracted_text
        { "url" => version.source_url, "sha256" => version.sha256, "starts_at" => stage.meeting.starts_at.iso8601,
          "text_sha256" => Digest::SHA256.hexdigest(stage.source_text), "kind" => stage.kind,
          "agenda" => portable_agenda(stage.input_manifest), "input_key" => stage.input_key, "data" => stage.data }
      end
    end

    def self.apply(meeting, records)
      input = Minutes::Input.new(meeting)
      version = input.text_version&.meeting_document_version
      return unless version
      records.each do |row|
        kind = row.fetch("kind")
        next unless Time.iso8601(row.fetch("starts_at")) == meeting.starts_at && version.source_url == row.fetch("url") &&
          version.sha256 == row.fetch("sha256") && Digest::SHA256.hexdigest(input.text) == row.fetch("text_sha256")
        # An empty original agenda supplied no item references. Keep that provenance when the
        # destination can now resolve a textual motion reference against an agenda.
        agenda = row.fetch("agenda")
        next unless agenda.empty? || agenda == portable_agenda(input.manifest(kind))
        next if input.completed_stage(kind)
        stage = MinutesExtraction.find_or_initialize_by(input_key: input.key(kind))
        next unless stage.new_record?
        stage.assign_attributes(input.stage_attributes(meeting, kind))
        locations = Minutes::LocateEvidence.new(stage).call(row.fetch("data")) if kind == "votes"
        provenance = { "input_key" => row.fetch("input_key"), "original_agenda" => agenda }
        stage.update!(status: "completed", data: row.fetch("data").merge("reviewed_import" => provenance), evidence_locations: locations || {}, completed_at: Time.current)
      end
    end

    def self.preserve_published_votes!(meeting, actor:, agenda:)
      raise ArgumentError, "Active administrator required" unless actor&.admin? && actor.active_for_authentication?
      raise ArgumentError, "Outside historical window" unless meeting.starts_at.to_date.between?(Batch::FIRST, Batch::LAST)
      meeting.with_lock do
        document = meeting.latest_document("agenda_pdf")
        raise ArgumentError, "Reviewed agenda source changed" unless document && document == agenda &&
          document.current_source_version&.sha256.present? && document.current_source_version.sha256 == document.sha256

        input = Minutes::Input.new(meeting)
        stage = meeting.minutes_publication&.votes_extraction
        receipt = input.supplemental_agenda_receipt(stage, agenda: document)
        raise ArgumentError, "Published votes require reconciliation" unless receipt
        return if meeting.processing_state["reviewed_supplemental_agenda"] == receipt
        raise ArgumentError, "A different agenda was already reviewed" if meeting.processing_state["reviewed_supplemental_agenda"].present?

        meeting.update!(processing_state: meeting.processing_state.merge("reviewed_supplemental_agenda" => receipt))
        AuditEvent.record!(actor: actor, action: "council_history.review_supplemental_agenda", subject: meeting,
          label: "Preserve minutes-based votes after reviewing a recovered agenda",
          metadata: receipt.merge("publication_id" => meeting.minutes_publication_id))
      end
    end

    def self.portable_agenda(manifest)
      Array(manifest["agenda"]).map { |_, number, title, _, parent, display| [ number, title, parent, display ] }
    end
    private_class_method :portable_agenda
  end
end
