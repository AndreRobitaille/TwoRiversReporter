module Documents
  class OcrJob < ApplicationJob
    queue_as :default

    def perform(document_id)
      document = MeetingDocument.find(document_id)
      return unless document.file.attached?

      # Mark as processing
      document.update!(ocr_status: "processing")

      Dir.mktmpdir do |dir|
        # Download PDF
        pdf_path = File.join(dir, "source.pdf")
        File.binwrite(pdf_path, document.file.download)

        # Convert to images (pdftoppm)
        # -r 300 for 300 DPI (good for OCR)
        unless system("pdftoppm", "-png", "-r", "300", pdf_path, File.join(dir, "page"))
          Rails.logger.error "pdftoppm failed for doc #{document_id}"
          document.update!(ocr_status: "failed")
          return
        end

        # Process each image with Tesseract
        images = Dir.glob(File.join(dir, "page-*.png")).sort_by { |f| f[/\d+/].to_i }

        # Clear existing extractions
        document.extractions.destroy_all

        full_text_parts = []

        images.each_with_index do |image_path, index|
          page_num = index + 1

          # Run Tesseract
          # tesseract image.png stdout
          text = `tesseract "#{image_path}" stdout 2>/dev/null`

          clean_text = text.scan(/\S+/).reject { |w| w.length > 250 }.join(" ")

          Extraction.create!(
            meeting_document: document,
            page_number: page_num,
            raw_text: text,
            cleaned_text: clean_text
          )

          full_text_parts << clean_text
        end

        # Update document
        full_text = full_text_parts.join(" ")
        document.update!(
          extracted_text: full_text,
          ocr_status: "completed",
          text_quality: "ocr"
        )

        # Trigger Downstream Jobs
        if document.document_type.include?("minutes") || document.document_type.include?("packet")
          SummarizeMeetingJob.perform_later(document.meeting_id)
        end
        if document.document_type == "minutes_pdf"
          ExtractVotesJob.perform_later(document.meeting_id)
        end

        Rails.logger.info "OCR completed for Document #{document_id} (#{images.count} pages)"
      end
    rescue StandardError => e
      Rails.logger.error "OCR failed for Document #{document_id}: #{e.message}"
      document.update!(ocr_status: "failed")
    end
  end
end
