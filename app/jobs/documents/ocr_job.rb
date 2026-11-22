require "open3"

module Documents
  class OcrJob < ApplicationJob
    queue_as :default

    def perform(document_id)
      document = MeetingDocument.find(document_id)
      return unless document.file.attached?

      publisher = PublishText.new(document)
      return if publisher.cached?("ocr_v1")
      publisher.mark!(ocr_status: "processing")

      Dir.mktmpdir do |dir|
        # Download PDF
        pdf_path = File.join(dir, "source.pdf")
        File.binwrite(pdf_path, publisher.blob.download)

        pdf_info, info_status = Open3.capture2e("pdfinfo", pdf_path)
        page_count = pdf_info[/^Pages:\s+(\d+)$/, 1].to_i
        raise "pdfinfo failed" unless info_status.success? && page_count.positive?

        # Convert to images (pdftoppm)
        # -r 300 for 300 DPI (good for OCR)
        unless system("pdftoppm", "-png", "-r", "300", pdf_path, File.join(dir, "page"))
          raise "pdftoppm failed"
        end

        images = Dir.glob(File.join(dir, "page-*.png")).sort_by do |path|
          File.basename(path)[/page-(\d+)\.png\z/, 1].to_i
        end
        raise "OCR produced no pages" if images.empty?
        numbers = images.map { |path| File.basename(path)[/page-(\d+)\.png\z/, 1].to_i }
        raise "OCR page sequence is incomplete" unless numbers == (1..page_count).to_a

        raw_pages = images.map do |image_path|
          text, _, status = Open3.capture3("tesseract", image_path, "stdout")
          raise "tesseract failed" unless status.success?
          text
        end
        raise "OCR produced no text" if raw_pages.all?(&:blank?)

        changed = publisher.call(raw_pages: raw_pages, page_count: page_count,
          quality: "ocr", extractor_version: "ocr_v1", ocr_status: "completed")
        return unless changed

        trigger_downstream_jobs(document)

        Rails.logger.info "OCR completed for Document #{document_id} (#{images.count} pages)"
      end
    rescue StandardError => e
      Rails.logger.error "OCR failed for Document #{document_id}: #{e.message}"
      publisher&.mark!(ocr_status: "failed")
    end

    private

    def trigger_downstream_jobs(document)
      if document.document_type.include?("packet")
        SummarizeMeetingJob.perform_later(document.meeting_id)
      end

      return unless document.document_type == "minutes_pdf"

      parse_result = :noop

      if Scrapers::ParseAgendaJob.meeting_has_usable_agenda_source?(document.meeting)
        begin
          parse_result = Scrapers::ParseAgendaJob.parse_and_reconcile(document.meeting_id)
        rescue StandardError => e
          Rails.logger.warn "Agenda reconciliation failed for Meeting #{document.meeting_id}: #{e.message}"
          parse_result = :noop
        end
      end

      ExtractTopicsJob.perform_later(document.meeting_id) if parse_result == :noop

      ExtractVotesJob.perform_later(document.meeting_id)
      ExtractCommitteeMembersJob.perform_later(document.meeting_id)
      SummarizeMeetingJob.set(wait: 10.minutes).perform_later(document.meeting_id)
    end
  end
end
