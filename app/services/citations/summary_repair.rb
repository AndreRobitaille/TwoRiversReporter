require "digest"

module Citations
  # Explicit, bounded repair: no AI calls, follow-up jobs, or official writes.
  # Legacy combined-source inputs cannot identify the source of each old page
  # label, so they are intentionally refused instead of attributed by guesswork.
  class SummaryRepair
    class Unprovable < StandardError; end
    SERVER_FIELDS = %w[source_type framing source_catalog citation_schema_version citation_provenance].freeze

    def initialize(summary_id:, prompt_run_id:, document_id:)
      @summary_id = summary_id
      @prompt_run_id = prompt_run_id
      @document_id = document_id
    end

    def call(apply: false, expected: {})
      MeetingSummary.transaction do
        summary = MeetingSummary.lock.find(@summary_id)
        run = PromptRun.lock.find(@prompt_run_id)
        document = MeetingDocument.lock.find(@document_id)
        document.extractions.lock.load
        prove_identity!(summary, run, document)
        before = protected_digest(summary)
        data = replacement_data(summary, run, document)
        changes = citation_changes(summary.generation_data, data)
        changed = data != summary.generation_data
        proof = { input_sha256: Digest::SHA256.hexdigest(run.placeholder_values.fetch("doc_text")),
          protected_sha256: before, source_version: data["source_catalog"].first["source_version"] }
        expected.each do |key, value|
          raise Unprovable, "Dry-run proof changed: #{key}" unless proof.fetch(key) == value
        end
        summary.update!(generation_data: data) if apply && changed
        raise Unprovable, "Protected reporting or official records changed" unless protected_digest(summary) == before

        { summary_id: summary.id, meeting_id: summary.meeting_id, document_id: document.id,
          prompt_run_id: run.id, source_type: document.document_type, source_url: document.source_url,
          changed: changed, applied: apply && changed,
          citation_changes: changes, **proof }
      end
    end

    # Citation keys are stripped only from the known reporting entries, never
    # from motion_evidence or arbitrary nested narrative/official fields.
    def self.reporting_data(data)
      result = data.deep_dup.except(*SERVER_FIELDS)
      MeetingAnalysis::SECTIONS.each do |section|
        Array(result[section]).each do |entry|
          entry.except!("citation", "citations") if entry.is_a?(Hash)
        end
      end
      result
    end

    private

    def prove_identity!(summary, run, document)
      raise Unprovable, "Wrong meeting or prompt" unless document.meeting_id == summary.meeting_id &&
        run.source_type == "Meeting" && run.source_id == summary.meeting_id && run.prompt_template_key == "analyze_meeting_content"
      data = summary.generation_data
      expected = { "transcript_recap" => "transcript", "minutes_recap" => "minutes_pdf",
        "packet_analysis" => "packet_pdf", "agenda_preview" => "agenda_pdf" }[summary.summary_type]
      source_type = { "transcript" => "transcript", "minutes_pdf" => "minutes", "packet_pdf" => "packet", "agenda_pdf" => "agenda" }[expected]
      raise Unprovable, "Summary source is ambiguous or incompatible" unless document.document_type == expected &&
        (data["source_type"].nil? || data["source_type"] == source_type)
      raise Unprovable, "Missing retained input" unless run.placeholder_values&.dig("doc_text").is_a?(String)
      raise Unprovable, "Response does not identify this reporting" unless self.class.reporting_data(JSON.parse(run.response_body)) ==
        self.class.reporting_data(data)

      text = run.placeholder_values["doc_text"]
      matches = summary.meeting.meeting_documents.where(document_type: expected).select do |candidate|
        retained_inputs(candidate).include?(text)
      end
      raise Unprovable, "Retained input does not uniquely identify the complete source" unless matches.map(&:id) == [ document.id ]
      # Require that the retained messages really supplied the retained input.
      raise Unprovable, "Retained messages do not contain the input" unless Array(run.messages).any? { |message|
        message.is_a?(Hash) && message["role"] == "user" && message["content"].to_s.include?(text)
      }
    rescue JSON::ParserError
      raise Unprovable, "Invalid retained response JSON"
    end

    def retained_inputs(document)
      return [] if document.extracted_text.blank?

      inputs = [ document.extracted_text, SourceCatalog.new(meeting: document.meeting, documents: [ document ]).text ]
      pages = SourceCatalog.pages_for(document)
      if pages.any? && pages.map(&:cleaned_text).join(" ").split.join(" ") == document.extracted_text.split.join(" ")
        inputs << pages.map { |page| "--- [Page #{page.page_number}] ---\n#{page.cleaned_text}" }.join("\n\n")
      end
      inputs
    end

    def replacement_data(summary, run, document)
      data = summary.generation_data.deep_dup
      catalog = SourceCatalog.new(meeting: summary.meeting, documents: [ document ])
      resolver = Resolver.new(meeting: summary.meeting, catalog: catalog.sources)
      MeetingAnalysis::SECTIONS.each do |section|
        Array(data[section]).each do |entry|
          next unless entry.is_a?(Hash) && (entry.key?("citations") || entry.key?("citation"))

          values = entry["citations"] || entry["citation"]
          references = values.is_a?(Array) ? values : [ values ].compact
          entry["citations"] = references.map do |reference|
            if reference.is_a?(Hash) && reference["source_id"]
              resolver.canonical_reference(reference)
            else
              location = legacy_location(reference, document, run, catalog)
              resolver.canonical_reference({ "source_id" => "doc-#{document.id}", "location" => location })
            end
          end.uniq
          entry.delete("citation")
        end
      end
      data["source_catalog"] = catalog.sources
      data["citation_schema_version"] = 1
      data["citation_provenance"] = { "repair" => "retained_input_v1", "prompt_run_id" => run.id,
        "input_sha256" => Digest::SHA256.hexdigest(run.placeholder_values["doc_text"]) }
      data
    end

    def legacy_location(reference, document, run, catalog)
      label = reference.is_a?(Hash) ? reference["label"] : reference
      page = label.is_a?(String) && label.match(/\A(?:#{Regexp.escape(document.document_type.split('_').first.capitalize)} )?Page (\d+)\z/i)&.[](1)&.to_i
      page_text = SourceCatalog.pages_for(document).map { |entry| "--- [Page #{entry.page_number}] ---\n#{entry.cleaned_text}" }.join("\n\n")
      input_has_pages = [ catalog.text, page_text ].include?(run.placeholder_values["doc_text"])
      if page && input_has_pages && catalog.sources.first["pages"].any? { |entry| entry["page_number"] == page }
        { "kind" => "pdf_page", "page_number" => page }
      else
        { "kind" => "whole_source" }
      end
    end

    def citation_changes(before, after)
      MeetingAnalysis::SECTIONS.flat_map do |section|
        Array(after[section]).each_with_index.filter_map do |entry, index|
          next unless entry.is_a?(Hash)
          old = Array(before[section])[index]
          previous = old&.slice("citation", "citations")
          replacement = entry.slice("citation", "citations")
          { path: "#{section}[#{index}]", agenda_item_id: entry["agenda_item_id"], before: previous, after: replacement } if previous != replacement
        end
      end
    end

    def protected_digest(summary)
      meeting = summary.meeting
      Digest::SHA256.hexdigest(JSON.generate({
        summary: summary.attributes.except("generation_data", "updated_at"),
        reporting: self.class.reporting_data(summary.generation_data),
        summary_source: summary.generation_data.slice("source_type", "framing"), meeting: meeting.attributes,
        agenda_items: meeting.agenda_items.order(:id).map(&:attributes),
        documents: meeting.meeting_documents.order(:id).map(&:attributes),
        extractions: Extraction.joins(:meeting_document).where(meeting_documents: { meeting_id: meeting.id }).order(:id).map(&:attributes),
        motions: meeting.motions.order(:id).map(&:attributes),
        votes: Vote.joins(:motion).where(motions: { meeting_id: meeting.id }).order(:id).map(&:attributes)
      }))
    end
  end
end
