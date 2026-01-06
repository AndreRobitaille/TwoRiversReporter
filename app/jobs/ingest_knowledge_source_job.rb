class IngestKnowledgeSourceJob < ApplicationJob
  queue_as :default

  def perform(source_id)
    source = KnowledgeSource.find(source_id)

    # 1. Extract text based on type
    full_text = case source.source_type
    when "note"
                  source.body
    when "pdf"
                  extract_pdf_text(source)
    else
                  nil
    end

    return if full_text.blank?

    # 2. Chunk text (simple sliding window for now)
    chunks = chunk_text(full_text)

    # 3. Embed and save chunks
    source.knowledge_chunks.destroy_all # Re-ingest (idempotent)

    embedding_service = ::Ai::EmbeddingService.new

    chunks.each_with_index do |chunk_content, index|
      embedding = embedding_service.embed(chunk_content)

      source.knowledge_chunks.create!(
        chunk_index: index,
        content: chunk_content,
        embedding: embedding,
        metadata: { char_length: chunk_content.length }
      )
    end
  end

  private

  def extract_pdf_text(source)
    return unless source.file.attached?

    source.file.open do |file|
      # Use pdftotext (same as AnalyzePdfJob)
      `pdftotext "#{file.path}" - 2>/dev/null`
    end
  end

  def chunk_text(text, max_chars: 2000, overlap: 200)
    chunks = []
    return chunks if text.blank?

    start = 0
    text_len = text.length

    while start < text_len
      end_pos = [ start + max_chars, text_len ].min

      # Try to break at a newline if possible near the end
      if end_pos < text_len
        last_newline = text.rindex("\n", end_pos)
        if last_newline && last_newline > start + (max_chars / 2)
          end_pos = last_newline
        end
      end

      chunks << text[start...end_pos].strip
      break if end_pos == text_len

      start = end_pos - overlap
    end

    chunks
  end
end
