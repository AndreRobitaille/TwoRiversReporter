class RetrievalService
  def initialize
    @embedding_service = ::Ai::EmbeddingService.new
  end

  def retrieve_context(query_text, limit: 10, candidate_scope: nil)
    return [] if query_text.blank?

    query_embedding = @embedding_service.embed(query_text)

    # Base scope: Active knowledge chunks
    scope = KnowledgeChunk.joins(:knowledge_source).where(knowledge_sources: { active: true })

    # Apply candidate scope if provided (e.g. topic filter)
    scope = scope.merge(candidate_scope) if candidate_scope

    # In production with pgvector:
    # scope.nearest_neighbors(:embedding, query_embedding, distance: "cosine").limit(limit)

    # In dev with pure Ruby fallback:
    all_chunks = scope.to_a
    results = VectorService.nearest_neighbors(query_embedding, all_chunks, top_k: limit)

    results
  end

  # Topic-aware retrieval with strict caps and determinism
  def retrieve_topic_context(topic:, query_text:, limit: 5, max_chars: 6000)
    # 0. Build topic-specific scope
    # Only include chunks from knowledge sources linked to this topic
    topic_scope = KnowledgeChunk.joins(knowledge_source: :knowledge_source_topics)
                                .where(knowledge_source_topics: { topic_id: topic.id })

    # 1. Fetch candidates with topic filter
    candidates = retrieve_context(query_text, limit: limit * 3, candidate_scope: topic_scope)

    # 2. Apply caps (count and size)
    final_results = []
    current_chars = 0

    candidates.each do |result|
      chunk_size = result[:chunk].content.length

      # Stop if we hit the count limit
      break if final_results.size >= limit

      # Stop if this chunk would exceed the char limit (unless we have nothing)
      if current_chars + chunk_size > max_chars && final_results.any?
        break
      end

      final_results << result
      current_chars += chunk_size
    end

    final_results
  end

  # Helper to format retrieved chunks for the LLM prompt
  def format_context(results)
    return "No relevant background context found." if results.empty?

    results.map do |result|
      chunk = result[:chunk]
      source = chunk.knowledge_source

      <<~TEXT
        [Source: #{source.title}] (Trust: #{source.verification_notes.present? ? 'Verified' : 'Unverified'})
        #{chunk.content}
      TEXT
    end.join("\n\n")
  end

  # Formatter for topic context with strict provenance labeling
  # Returns an Array of strings, not joined, for safer handling
  def format_topic_context(results)
    return [] if results.empty?

    results.map do |result|
      chunk = result[:chunk]
      source = chunk.knowledge_source
      trust_label = source.verification_notes.present? ? "VERIFIED" : "UNVERIFIED"

      <<~TEXT
        [Source: #{source.title} | ID: #{source.id} | Status: #{trust_label}]
        #{chunk.content}
      TEXT
    end
  end
end
