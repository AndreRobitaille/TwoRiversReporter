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
        text = `pdftotext "#{path}" - 2>/dev/null`
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
        document.update!(
          page_count: page_count,
          text_chars: char_count,
          avg_chars_per_page: avg,
          text_quality: quality
        )
      end
    rescue StandardError => e
      document.update!(text_quality: "broken")
      Rails.logger.error("PDF Analysis failed for Document #{document_id}: #{e.message}")
    end
  end
end
