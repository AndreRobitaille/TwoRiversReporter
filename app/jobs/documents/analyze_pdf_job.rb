require "open3"

module Documents
  class AnalyzePdfJob < ApplicationJob
    queue_as :default

    def perform(document_id)
      document = MeetingDocument.find(document_id)
      return unless document.file.attached?

      publisher = PublishText.new(document)
      if publisher.cached?("pdf_text_v1")
        OcrJob.perform_later(document.id) if document.text_quality == "image_scan"
        return
      end

      publisher.blob.open do |file|
        pdf_info, info_status = Open3.capture2e("pdfinfo", file.path)
        page_count = pdf_info[/^Pages:\s+(\d+)$/, 1].to_i
        raise "pdfinfo failed" unless info_status.success? && page_count.positive?

        raw_full_text, _, text_status = Open3.capture3("pdftotext", file.path, "-")
        raise "pdftotext failed" unless text_status.success?

        # Preserve blank pages and remove only the final page separator.
        raw_pages = raw_full_text.split("\f", -1)
        raw_pages.pop if raw_full_text.end_with?("\f")
        raw_pages = Array.new(page_count, "") if raw_full_text.blank?
        char_count = raw_pages.sum { |page| page.scan(/\S+/).reject { |word| word.length > 250 }.join(" ").length }
        average = char_count.to_f / page_count
        quality = if average >= 200
          "text"
        elsif average >= 20
          "mixed"
        else
          "image_scan"
        end

        changed = publisher.call(raw_pages: raw_pages, page_count: page_count,
          quality: quality, extractor_version: "pdf_text_v1")
        return unless changed

        # Trigger OCR if needed
        if quality == "image_scan"
          OcrJob.perform_later(document.id)
          return
        end

        # Trigger Summarization for packet documents immediately
        if document.document_type.include?("packet")
          SummarizeMeetingJob.perform_later(document.meeting_id)
        end

        # Trigger Vote, Membership, and Topic Extraction for minutes
        # SummarizeMeetingJob is delayed to run after extraction + triage complete
        if document.document_type == "minutes_pdf"
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

        # Trigger agenda preview summarization. Delay allows ParseAgendaJob
        # -> ExtractTopicsJob -> AutoTriageJob (3-min delay) to complete
        # first, so topic briefings refresh against approved topics.
        if document.document_type == "agenda_pdf"
          Scrapers::ParseAgendaJob.perform_later(document.meeting_id)
          SummarizeMeetingJob.set(wait: 5.minutes).perform_later(document.meeting_id, mode: :agenda_preview)
        end
      end
    rescue StandardError => e
      publisher&.mark!(text_quality: "broken", ocr_status: nil)
      Rails.logger.error("PDF Analysis failed for Document #{document_id}: #{e.message}")
    end
  end
end
