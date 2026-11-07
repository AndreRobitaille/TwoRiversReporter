require "digest"

module Topics
  # Dependency receipts are not factual approval. Private input text is hashed,
  # never copied into the generated analysis's publicly consumed JSON.
  class GenerationEvidence
    # Bump when context, retrieval, or generation policy changes in code.
    VERSION = 1

    def self.capture(topic:, meeting:, context:, query:, kind:)
      return unless topic.approved? && sources_current?(context[:source_catalog])

      input = { context: context.except(:knowledgebase_context), query: query,
        knowledge: knowledge_inputs(topic), prompts: prompt_inputs(kind),
        committees: Committee.for_ai_context.pluck(:name, :committee_type, :description) }
      { "version" => VERSION, "kind" => kind, "topic_id" => topic.id, "meeting_id" => meeting.id,
        "input_sha256" => Digest::SHA256.hexdigest(JSON.generate(canonical(input.as_json))),
        "motion_evidence" => motion_evidence(context) }
    end

    def self.summary_inputs(topic_id, meeting_id)
      ActiveRecord::Base.uncached do
        topic, meeting = Topic.find(topic_id), Meeting.find(meeting_id)
        linked = meeting.agenda_items.substantive.joins(:agenda_item_topics).where(agenda_item_topics: { topic_id: topic.id }).exists?
        return unless linked && topic.approved?

        context = SummaryContextBuilder.new(topic, meeting).build_context_json
        query = RetrievalQueryBuilder.new(topic, meeting).build_query
        evidence = capture(topic: topic, meeting: meeting, context: context, query: query, kind: "topic_summary")
        { context: context, query: query, evidence: evidence } if evidence
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def self.summary_current?(summary)
      data = summary.generation_data
      return false unless data.is_a?(Hash) && sources_current?(data["source_catalog"])
      # A legacy analysis has no dependency receipt. Do not invent one or label
      # it validated; still reject any known changed source in its catalog.
      return true unless data.key?("evidence_manifest")

      expected = summary_inputs(summary.topic_id, summary.meeting_id)&.fetch(:evidence)
      expected.present? && data["evidence_manifest"] == expected
    end

    def self.sources_current?(sources)
      return true if sources.nil? # Legacy provenance remains unknown.
      return false unless sources.is_a?(Array)

      sources.all? do |source|
        next false unless source.is_a?(Hash) && source["document_id"].is_a?(Integer)
        document = MeetingDocument.find_by(id: source["document_id"], meeting_id: source["meeting_id"])
        next false unless document
        snapshot = Citations::SourceCatalog.snapshot(document)
        source.slice(*snapshot.keys) == snapshot
      end
    end

    def self.knowledge_inputs(topic)
      chunks = KnowledgeChunk.joins(:knowledge_source)
        .where(knowledge_source_id: KnowledgeSourceTopic.where(topic_id: topic.id).select(:knowledge_source_id))
        .where(knowledge_sources: { active: true, status: "approved" })
        .includes(:knowledge_source).order(:id).to_a
      sources = chunks.map(&:knowledge_source).uniq(&:id).sort_by(&:id)
      # Include each source body once, not once per chunk of a long document.
      { sources: sources.map { |source| [ source.id, source.title, source.origin, source.stated_at, source.body ] },
        chunks: chunks.map { |chunk| [ chunk.id, chunk.knowledge_source_id, chunk.content, chunk.embedding ] } }
    end
    private_class_method :knowledge_inputs

    def self.prompt_inputs(kind)
      PromptTemplate.where(key: [ "analyze_#{kind}", "render_#{kind}" ]).order(:key).map do |template|
        [ template.key, template.system_role, template.instructions, template.model_tier,
          Ai::OpenAiService.model_for_tier(template.model_tier) ]
      end
    end
    private_class_method :prompt_inputs

    def self.motion_evidence(context)
      continuity = context[:continuity_context] || {}
      events = Array(continuity[:recent_status_events] || continuity[:status_events]).filter_map do |event|
        next unless event[:event_id]
        { "event_id" => event[:event_id], "reference" => event[:motion_reference]&.deep_stringify_keys }
      end
      inherited = Array(context[:prior_meeting_analyses]).flat_map do |analysis|
        Array(analysis.dig("evidence_manifest", "motion_evidence"))
      end
      (events + inherited).uniq.sort_by { |entry| entry.fetch("event_id") }
    end
    private_class_method :motion_evidence

    def self.canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |entry| canonical(entry) }
      when Array then value.map { |entry| canonical(entry) }
      else value
      end
    end
    private_class_method :canonical
  end
end
