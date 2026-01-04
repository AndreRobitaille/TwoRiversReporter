require "open-uri"
require "digest"

module Documents
  class DownloadJob < ApplicationJob
    queue_as :default

    def perform(document_id)
      document = MeetingDocument.find(document_id)
      return unless document.source_url.present?

      begin
        # Download stream
        downloaded_io = URI.open(document.source_url)

        # Compute SHA256
        # If it's a Tempfile, use path. If StringIO (small files), use string.
        sha = if downloaded_io.is_a?(Tempfile)
                Digest::SHA256.file(downloaded_io.path).hexdigest
        else
                Digest::SHA256.hexdigest(downloaded_io.read)
        end

        # Rewind for Active Storage
        downloaded_io.rewind

        # Filename
        filename = File.basename(URI.parse(document.source_url).path)
        filename = "document.pdf" if filename.blank?

        # Attach
        document.file.attach(
          io: downloaded_io,
          filename: filename
        )

        document.update!(
          sha256: sha,
          fetched_at: Time.current
        )

        # Trigger Analysis for PDFs
        if document.document_type.to_s.end_with?("pdf")
          Documents::AnalyzePdfJob.perform_later(document.id)
        end

      rescue OpenURI::HTTPError => e
        # Handle 404s etc
        Rails.logger.error "Failed to download document #{document_id}: #{e.message}"
      end
    end
  end
end
