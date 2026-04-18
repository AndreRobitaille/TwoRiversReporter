require "open3"

module Documents
  class AnalyzePdfJob < ApplicationJob
    queue_as :default

    def perform(document_id)
      document = MeetingDocument.find(document_id)
      return unless document.file.attached?

      document.file.open do |file|
        path = file.path

        # 1. Get Page Count via pdfinfo
        pdf_info, status = Open3.capture2e("pdfinfo", path)
        if status.success?
          page_count = pdf_info[/^Pages:\s+(\d+)$/, 1].to_i
        else
          Rails.logger.warn "pdfinfo failed for #{document_id}"
          page_count = 0
        end

        # 2. Extract Text via pdftotext
        # Output to stdout (-)
        # We split by Form Feed (\f) to separate pages
        raw_full_text, _, _ = Open3.capture3("pdftotext", path, "-")

        # Clear existing extractions to be idempotent
        document.extractions.destroy_all

        raw_pages = raw_full_text.split("\f")
        full_clean_text_parts = []

        raw_pages.each_with_index do |page_text, index|
          page_num = index + 1
          # Sanitize text: remove any token longer than 250 chars (likely garbage/binary)
          clean_page_text = page_text.scan(/\S+/).reject { |w| w.length > 250 }.join(" ")

          # Store granular page extraction
          Extraction.create!(
            meeting_document: document,
            page_number: page_num,
            raw_text: page_text,
            cleaned_text: clean_page_text
          )

          full_clean_text_parts << clean_page_text
        end

        text = full_clean_text_parts.join(" ")

        Rails.logger.info "Extracted #{raw_full_text.length} chars (cleaned to #{text.length}) from #{path} across #{raw_pages.size} pages"
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
      document.update!(text_quality: "broken")
      Rails.logger.error("PDF Analysis failed for Document #{document_id}: #{e.message}")
    end

  end
end
