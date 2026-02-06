require "open-uri"
require "digest"

module Documents
  class DownloadJob < ApplicationJob
    queue_as :default

    def perform(document_id)
      document = MeetingDocument.find(document_id)
      return unless document.source_url.present?

      # Prepare conditional GET headers
      headers = {}
      headers["If-None-Match"] = document.etag if document.etag.present?
      headers["If-Modified-Since"] = document.last_modified.httpdate if document.last_modified.present?

      begin
        # Download stream with conditional headers
        downloaded_io = URI.open(document.source_url, headers)

        # Extract remote metadata
        remote_etag = downloaded_io.meta["etag"]
        remote_last_modified = downloaded_io.meta["last-modified"] ? DateTime.parse(downloaded_io.meta["last-modified"]) : nil
        remote_content_length = downloaded_io.meta["content-length"]&.to_i

        # Compute SHA256
        sha = if downloaded_io.is_a?(Tempfile)
                Digest::SHA256.file(downloaded_io.path).hexdigest
        else
                Digest::SHA256.hexdigest(downloaded_io.read)
        end

        # Rewind for subsequent use
        downloaded_io.rewind

        # Check if content changed (by SHA)
        if document.sha256 == sha
          Rails.logger.info "Document #{document_id} unchanged (SHA match)"

          # Update metadata even if content is same (e.g. headers changed or just to mark checked)
          document.update!(
            etag: remote_etag,
            last_modified: remote_last_modified,
            content_length: remote_content_length,
            fetched_at: Time.current
          )
          return
        end

        # Content changed
        Rails.logger.info "Document #{document_id} updated/replaced (new SHA: #{sha})"

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
          etag: remote_etag,
          last_modified: remote_last_modified,
          content_length: remote_content_length,
          fetched_at: Time.current
        )

        # Trigger Analysis for PDFs or Agenda parsing
        if document.document_type.to_s.end_with?("pdf")
          Documents::AnalyzePdfJob.perform_later(document.id)
        elsif document.document_type == "agenda_html"
          Scrapers::ParseAgendaJob.perform_later(document.meeting_id)
        end

      rescue OpenURI::HTTPError => e
        if e.io&.status&.first == "304"
          Rails.logger.info "Document #{document_id} unchanged (304 Not Modified)"
          document.touch(:fetched_at)
        else
          Rails.logger.error "Failed to download document #{document_id}: #{e.message} (status: #{e.io&.status.inspect})"
        end
      rescue StandardError => e
        Rails.logger.error "Error processing document #{document_id}: #{e.message}"
      end
    end
  end
end
