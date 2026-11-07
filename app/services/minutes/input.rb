require "digest"

module Minutes
  class Input
    class Unavailable < StandardError; end
    TASKS = { "votes" => "extract_votes", "attendance" => "extract_committee_members" }.freeze

    attr_reader :document, :text_version, :text, :agenda_items, :source_manifest, :source_key

    def initialize(meeting)
      @document = meeting.meeting_documents.where(document_type: "minutes_pdf").order(created_at: :desc, id: :desc).first
      raise Unavailable unless document&.extracted_text.present?
      @text_version = document.current_text_version
      if document.source_versions.exists?
        raise Unavailable unless text_version && text_version.extracted_text == document.extracted_text &&
          document.file.attached? && document.file.blob.checksum == text_version.meeting_document_version.file.blob.checksum
      end
      @text = document.extracted_text.dup.freeze
      @agenda_items = meeting.agenda_items.substantive.ordered.includes(:parent).to_a
      @source_manifest = Citations::SourceCatalog.snapshot(document).merge(
        "text_version_id" => text_version&.id,
        "provenance" => text_version ? "retained_artifact" : "legacy_text_projection"
      )
      @source_key = digest(source_manifest)
      @templates = TASKS.transform_values { |task| PromptTemplate.find_by(key: task) }
      @manifests = TASKS.to_h { |kind, task| [ kind, template_manifest(task, @templates.fetch(kind)) ] }
    end

    def template(kind)
      @templates.fetch(kind)
    end

    def manifest(kind)
      data = { "source" => source_manifest, "kind" => kind, "rules" => "minutes_facts_v1", "provider" => @manifests.fetch(kind) }
      if kind == "votes"
        data["agenda"] = agenda_items.map { |item| [ item.id, item.number, item.title, item.parent_id, item.parent&.title, item.display_context_title ] }
      end
      data
    end

    def key(kind)
      digest(manifest(kind))
    end

    def agenda_text
      agenda_items.map do |item|
        label = item.number.present? ? "#{item.number}: #{item.title}" : item.title
        item.parent ? "#{label} (#{item.parent.title})" : label
      end.join("\n")
    end

    def stage_attributes(meeting, kind)
      { meeting: meeting, original_meeting_id: meeting.id, meeting_document_text_version: text_version,
        kind: kind, input_key: key(kind), source_key: source_key, input_manifest: manifest(kind), source_text: text }
    end

    private

    def template_manifest(task, template)
      { "task" => task, "template" => template&.attributes&.slice("instructions", "system_role", "model_tier"),
        "model" => Ai::OpenAiService.model_for_tier(template&.model_tier) }
    end

    def digest(data)
      Digest::SHA256.hexdigest(JSON.generate(data))
    end
  end
end
