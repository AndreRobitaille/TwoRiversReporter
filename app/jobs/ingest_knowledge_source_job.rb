require "open3"

class IngestKnowledgeSourceJob < ApplicationJob
  queue_as :default

  def perform(source_id)
    source = KnowledgeSource.find(source_id)
    return unless source.available?
    expected = input_version(source)

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

    # Providers run outside locks. Preserve the existing chunks on a failure or
    # stale response, and publish the complete replacement only if still current.
    embedding_service = ::Ai::EmbeddingService.new
    values = chunks.map.with_index do |chunk_content, index|
      {
        chunk_index: index,
        content: chunk_content,
        embedding: embedding_service.embed(chunk_content),
        metadata: { char_length: chunk_content.length }
      }
    end

    KnowledgeSource.transaction do
      current = KnowledgeSource.available.lock("FOR NO KEY UPDATE").find_by(id: source_id)
      next unless current && input_version(current) == expected

      current.knowledge_chunks.destroy_all
      values.each { |attributes| current.knowledge_chunks.create!(attributes) }
    end
  end

  private

  def input_version(source)
    source.attributes.slice("source_type", "body").merge("blob_id" => source.file_attachment&.blob_id)
  end

  def extract_pdf_text(source)
    return unless source.file.attached?

    source.file.open do |file|
      # Use pdftotext (same as AnalyzePdfJob)
      stdout, _, _ = Open3.capture3("pdftotext", file.path, "-")
      stdout
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
