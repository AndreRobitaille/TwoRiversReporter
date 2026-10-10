require "digest"

module Citations
  # A snapshot of exactly the documents supplied to one analysis. This lives
  # with the summary, independently of the short-lived PromptRun retention.
  class SourceCatalog
    class InvalidSource < StandardError; end

    attr_reader :sources, :text

    def initialize(meeting:, documents:)
      @sources = []
      @text = documents.map do |document|
        raise InvalidSource, "Source belongs to another meeting" unless document.meeting_id == meeting.id
        raise InvalidSource, "Source has no extracted text" if document.extracted_text.blank?

        pages = self.class.pages_for(document)
        @sources << self.class.snapshot(document, pages: pages)
        body = document.extracted_text
        if pages.any?
          page_text = pages.map { |page| "--- [Page #{page.page_number}] ---\n#{page.cleaned_text}" }.join("\n\n")
          # Never discard text when page extractions are incomplete or stale.
          body = if normalize(pages.map(&:cleaned_text).join(" ")) == normalize(body)
            page_text
          else
            "#{body}\n\nPage extractions:\n#{page_text}"
          end
        end
        "--- Source doc-#{document.id} (#{document.document_type}) ---\n#{body}"
      end.join("\n\n")
    end

    def self.pages_for(document)
      return [] unless document.document_type.to_s.end_with?("_pdf") && document.page_count.to_i.positive?

      pages = document.extractions.order(:page_number, :id).to_a
      counts = pages.group_by(&:page_number).transform_values(&:size)
      document_text = document.extracted_text.to_s.split.join(" ")
      pages.select do |page|
        page.page_number.is_a?(Integer) && page.page_number.between?(1, document.page_count) &&
          counts[page.page_number] == 1 && page.cleaned_text.present? &&
          document_text.include?(page.cleaned_text.split.join(" "))
      end
    end

    def self.snapshot(document, pages: pages_for(document))
      data = {
        "source_id" => "doc-#{document.id}", "document_id" => document.id,
        "meeting_id" => document.meeting_id, "document_type" => document.document_type,
        "source_url" => document.source_url, "artifact_sha256" => document.sha256,
        "attachment_checksum" => document.file.attached? ? document.file.blob.checksum : nil,
        "text_sha256" => Digest::SHA256.hexdigest(document.extracted_text.to_s),
        "page_count" => document.page_count,
        "pages" => pages.map { |page| { "page_number" => page.page_number,
          "text_sha256" => Digest::SHA256.hexdigest(page.cleaned_text) } }
      }
      data.merge("source_version" => Digest::SHA256.hexdigest(JSON.generate(data)))
    end

    private

    def normalize(text)
      text.to_s.split.join(" ")
    end
  end
end
