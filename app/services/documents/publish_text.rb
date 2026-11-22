require "digest"

module Documents
  # Pins the input before external parsing, then publishes one complete result.
  # Legacy artifacts without retained download provenance get the same stale-work
  # guard and atomic projection, but cannot acquire a fabricated source version.
  class PublishText
    attr_reader :blob

    def initialize(document)
      @document = document
      @blob = document.file.blob
      @source_version = document.current_source_version
      if @source_version && @source_version.file.blob.checksum != @blob.checksum
        raise ArgumentError, "Attachment does not match retained source"
      end
      @input_state = state
    end

    def cached?(extractor_version)
      version = @document.current_text_version
      version && (version.extractor_version == extractor_version ||
        (extractor_version == "pdf_text_v1" && version.extractor_version == "ocr_v1"))
    end

    def call(raw_pages:, page_count:, quality:, extractor_version:, ocr_status: nil)
      pages = raw_pages.each_with_index.map do |raw_text, index|
        { "page_number" => index + 1, "raw_text" => raw_text,
          "cleaned_text" => raw_text.scan(/\S+/).reject { |word| word.length > 250 }.join(" ") }
      end
      raise ArgumentError, "Incomplete extracted page sequence" unless page_count.positive? && pages.size == page_count
      text = pages.map { |page| page.fetch("cleaned_text") }.join(" ")
      attributes = { page_count: page_count, extracted_text: text, text_chars: text.length,
        avg_chars_per_page: text.length.to_f / page_count, text_quality: quality, ocr_status: ocr_status }

      @document.with_lock do
        return false unless state == @input_state

        if @source_version
          data = { meeting_document_version_id: @source_version.id, extractor_version: extractor_version,
            page_count: page_count, text_quality: quality, extracted_text: text, pages: pages }
          fingerprint = Digest::SHA256.hexdigest(JSON.generate(data))
          version = MeetingDocumentTextVersion.find_by(fingerprint: fingerprint) ||
            MeetingDocumentTextVersion.create!(**data, fingerprint: fingerprint)
          attributes[:latest_text_version_id] = version.id
        end

        existing_pages = @document.extractions.order(:page_number).map { |page| page.attributes.slice("page_number", "raw_text", "cleaned_text") }
        return false if attributes.all? { |key, value| @document.public_send(key) == value } && existing_pages == pages

        @document.extractions.destroy_all
        pages.each { |page| @document.extractions.create!(page) }
        @document.update!(attributes)
      end
      true
    end

    def mark!(attributes)
      @document.with_lock { @document.update!(attributes) if state == @input_state }
    rescue ActiveRecord::RecordNotFound
      nil
    end

    private

    def state
      [ @document.source_url, @document.document_type, @document.sha256,
        @document.file.blob&.id, @document.latest_text_version_id ]
    end
  end
end
