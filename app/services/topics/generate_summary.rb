module Topics
  class GenerateSummary
    def initialize(topic, meeting, ai_service:, retrieval_service:)
      @topic, @meeting = topic, meeting
      @ai_service, @retrieval_service = ai_service, retrieval_service
    end

    def call
      input = GenerationEvidence.summary_inputs(@topic.id, @meeting.id)
      return unless input
      @evidence = input.fetch(:evidence)
      existing = summary
      return existing if existing&.generation_data.is_a?(Hash) && existing.generation_data["evidence_manifest"] == @evidence
      original = existing&.attributes&.slice("id", "updated_at")

      chunks = @retrieval_service.retrieve_topic_context(topic: @topic, query_text: input.fetch(:query), limit: 5, max_chars: 6000)
      context = input.fetch(:context).merge(knowledgebase_context: @retrieval_service.format_topic_context(chunks))
      return unless evidence_current?

      response = @ai_service.analyze_topic_summary(context, source: @topic)
      return if response.blank?
      data = JSON.parse(response)
      raise JSON::ParserError, "Expected topic analysis object" unless data.is_a?(Hash)
      return unless evidence_current?

      Citations::TopicAnalysis.copy_references!(data, references: context[:citation_references],
        require_citations: %w[factual_record institutional_framing])
      data["source_catalog"] = context[:source_catalog].deep_dup
      data["evidence_manifest"] = @evidence.deep_dup
      content = @ai_service.render_topic_summary(data.to_json, source: @topic)

      @topic.with_lock do
        current = summary
        return unless current&.attributes&.slice("id", "updated_at") == original && evidence_current?

        current ||= TopicSummary.new(topic: @topic, meeting: @meeting, summary_type: "topic_digest")
        current.update!(content: content, generation_data: data)
        score = data.dig("resident_impact", "score").to_i if data["resident_impact"].is_a?(Hash)
        @topic.update_resident_impact_from_ai(score) if score&.between?(1, 5)
        current
      end
    end

    private

    def summary
      TopicSummary.find_by(topic: @topic, meeting: @meeting, summary_type: "topic_digest")
    end

    def evidence_current?
      GenerationEvidence.summary_inputs(@topic.id, @meeting.id)&.fetch(:evidence) == @evidence
    end
  end
end
