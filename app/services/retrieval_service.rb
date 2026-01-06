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
end
