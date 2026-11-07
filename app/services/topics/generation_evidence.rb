require "digest"

module Topics
  # Dependency receipts are not factual approval. Private input text is hashed,
  # never copied into the generated analysis's publicly consumed JSON.
  class GenerationEvidence
    # Receipt format and generation policy are separate: policy changes require
    # new generation, without declaring supported historical evidence invalid.
    VERSION = 1
    POLICY_VERSION = 1

    def self.capture(topic:, meeting:, context:, query:, kind:)
      return unless topic.approved? && sources_current?(context[:source_catalog])

      knowledge = knowledge_inputs(topic)
      input = { policy_version: POLICY_VERSION, context: context.except(:knowledgebase_context), query: query,
        knowledge: knowledge, prompts: prompt_inputs(kind),
        committees: Committee.for_ai_context.pluck(:name, :committee_type, :description) }
      { "version" => VERSION, "kind" => kind, "topic_id" => topic.id, "meeting_id" => meeting.id,
        "input_sha256" => fingerprint(input),
        "meeting_sha256" => fingerprint(context[:meeting_metadata]),
        "background_sha256" => fingerprint(context.slice(:background_context, :resident_reported_context)),
        "agenda_evidence" => Array(context[:agenda_items]).map { |item| fingerprint(item) },
        "knowledge_evidence" => knowledge_references(knowledge),
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

      retained = data["evidence_manifest"]
      expected = summary_inputs(summary.topic_id, summary.meeting_id)&.fetch(:evidence)
      return false unless retained.is_a?(Hash) && expected

      # New appearances, aliases, prompts or additional background change the
      # generation cache key, but do not invalidate supported historical facts.
      fixed = %w[version kind meeting_id meeting_sha256 background_sha256]
      return false unless retained.slice(*fixed) == expected.slice(*fixed)
      return false unless %w[agenda_evidence knowledge_evidence].all? do |key|
        retained[key].is_a?(Array) && (retained[key] - expected.fetch(key)).empty?
      end

      events = retained["motion_evidence"]
      motion_evidence_current?(summary.topic_id, events)
    end

    def self.motion_evidence_current?(topic_id, events)
      return false unless events.is_a?(Array) && events.all? { |event| event.is_a?(Hash) && event["event_id"].is_a?(Integer) }
      current = TopicStatusEvent.where(topic_id: topic_id, id: events.map { |event| event["event_id"] }).with_current_evidence
      (events - current.map { |event| event_reference(event) }).empty?
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

    def self.knowledge_references(knowledge)
      chunks_by_source = knowledge.fetch(:chunks).group_by { |chunk| chunk[1] }
      knowledge.fetch(:sources).map do |source|
        fingerprint([ source, chunks_by_source.fetch(source.first, []) ])
      end
    end
    private_class_method :knowledge_references

    def self.prompt_inputs(kind)
      PromptTemplate.where(key: [ "analyze_#{kind}", "render_#{kind}" ]).order(:key).map do |template|
        [ template.key, template.system_role, template.instructions, template.model_tier,
          Ai::OpenAiService.model_for_tier(template.model_tier) ]
      end
    end
    private_class_method :prompt_inputs

    def self.motion_evidence(context)
      continuity = context[:continuity_context] || {}
      ids = Array(continuity[:recent_status_events] || continuity[:status_events]).filter_map { |event| event[:event_id] }
      events = TopicStatusEvent.where(id: ids).map { |event| event_reference(event) }
      inherited = Array(context[:prior_meeting_analyses]).flat_map do |analysis|
        Array(analysis.dig("evidence_manifest", "motion_evidence"))
      end
      (events + inherited).uniq.sort_by { |entry| entry.fetch("event_id") }
    end
    private_class_method :motion_evidence

    def self.event_reference(event)
      { "event_id" => event.id, "reference" => event.motion_reference&.deep_stringify_keys,
        "event_sha256" => fingerprint(event.attributes.slice("evidence_type", "lifecycle_status", "occurred_at", "notes", "source_ref")) }
    end
    private_class_method :event_reference

    def self.fingerprint(value)
      Digest::SHA256.hexdigest(JSON.generate(canonical(value.as_json)))
    end
    private_class_method :fingerprint

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
