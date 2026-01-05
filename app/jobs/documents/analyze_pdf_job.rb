module Documents
  class AnalyzePdfJob < ApplicationJob
    queue_as :default

    def perform(document_id)
      document = MeetingDocument.find(document_id)
      return unless document.file.attached?

      document.file.open do |file|
        path = file.path

        # 1. Get Page Count via pdfinfo
        pdf_info = `pdfinfo "#{path}" 2>&1`
        if $?.success?
          page_count = pdf_info[/^Pages:\s+(\d+)$/, 1].to_i
        else
          Rails.logger.warn "pdfinfo failed for #{document_id}"
          page_count = 0
        end

        # 2. Extract Text via pdftotext
        # Output to stdout (-)
        raw_text = `pdftotext "#{path}" - 2>/dev/null`

        # Sanitize text: remove any token longer than 250 chars (likely garbage/binary)
        # This prevents Postgres index failures
        Rails.logger.info "SANITIZING TEXT for doc #{document_id}..."
        text = raw_text.scan(/\S+/).reject { |w| w.length > 250 }.join(" ")

        Rails.logger.info "Extracted #{raw_text.length} chars (cleaned to #{text.length}) from #{path}"
        char_count = text.length

        # 3. Calculate Metrics
        avg = page_count > 0 ? char_count.to_f / page_count : 0.0

        quality = if page_count == 0
                    "broken"
        elsif avg >= 200
                    "text"
        elsif avg >= 20
                    "mixed"
        else
                    "image_scan"
        end

        # 4. Save
        unless document.update(
          page_count: page_count,
          text_chars: char_count,
          avg_chars_per_page: avg,
          text_quality: quality,
          extracted_text: text
        )
          Rails.logger.error "Failed to save analysis for #{document_id}: #{document.errors.full_messages.join(', ')}"
        end
        # Trigger Summarization if this was a minutes or packet document
        if document.document_type.include?("minutes") || document.document_type.include?("packet")
          SummarizeMeetingJob.perform_later(document.meeting_id)
        end
      end
    rescue StandardError => e
      document.update!(text_quality: "broken")
      Rails.logger.error("PDF Analysis failed for Document #{document_id}: #{e.message}")
    end
  end
end
