class RetrievalService
  def initialize
    @embedding_service = ::Ai::EmbeddingService.new
  end

  def retrieve_context(query_text, limit: 10)
    return [] if query_text.blank?

    query_embedding = @embedding_service.embed(query_text)

    # In production with pgvector:
    # KnowledgeChunk.nearest_neighbors(:embedding, query_embedding, distance: "cosine").limit(limit)

    # In dev with pure Ruby fallback:
    all_chunks = KnowledgeChunk.joins(:knowledge_source).where(knowledge_sources: { active: true })

    # If dataset is huge, this is slow. For <10k chunks, it's fine.
    # We load all embeddings into memory to compute dot product.

    results = VectorService.nearest_neighbors(query_embedding, all_chunks, top_k: limit)

    # Return array of { chunk: chunk_obj, score: float }
    results
  end

  # Topic-aware retrieval with strict caps and determinism
  def retrieve_topic_context(topic:, query_text:, limit: 5, max_chars: 6000)
    # 1. Fetch more candidates than needed to allow for size filtering
    # We fetch 3x the limit to have a buffer for skipping large/irrelevant chunks if we were filtering,
    # but primarily to ensure we have enough candidates to fill the caps.
    candidates = retrieve_context(query_text, limit: limit * 3)

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
