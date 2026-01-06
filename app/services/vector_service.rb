class VectorService
  # Pure Ruby implementation of cosine similarity for vector search.
  # Used when pgvector extension is not available.

  def self.cosine_similarity(vec_a, vec_b)
    return 0.0 if vec_a.empty? || vec_b.empty? || vec_a.size != vec_b.size

    dot_product = 0.0
    norm_a = 0.0
    norm_b = 0.0

    vec_a.each_with_index do |val_a, i|
      val_b = vec_b[i]
      dot_product += val_a * val_b
      norm_a += val_a ** 2
      norm_b += val_b ** 2
    end

    return 0.0 if norm_a.zero? || norm_b.zero?

    dot_product / (Math.sqrt(norm_a) * Math.sqrt(norm_b))
  end

  def self.nearest_neighbors(query_embedding, chunks, top_k: 5)
    scored = chunks.map do |chunk|
      # Handle JSON-stored embeddings (array of floats)
      chunk_embedding = chunk.embedding
      next if chunk_embedding.blank?

      score = cosine_similarity(query_embedding, chunk_embedding)
      { chunk: chunk, score: score }
    end.compact

    scored.sort_by { |item| -item[:score] }.take(top_k)
  end
end
