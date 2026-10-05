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

        metadata = fetch_metadata(downloaded_io)

        # Compute SHA256
        sha = if downloaded_io.is_a?(Tempfile)
                Digest::SHA256.file(downloaded_io.path).hexdigest
        else
                Digest::SHA256.hexdigest(downloaded_io.read)
        end

        # Rewind for subsequent use
        downloaded_io.rewind

        # Matching bytes are not a content change. Record last-checked time and
        # any cache headers without moving updated_at.
        if document.sha256 == sha
          Rails.logger.info "Document #{document_id} unchanged (SHA match)"
          record_unchanged_check!(document, **metadata)
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
          etag: metadata[:etag],
          last_modified: metadata[:last_modified],
          content_length: metadata[:content_length],
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
          # 304 means the stored bytes are still current. Refresh last-checked
          # time and whatever cache headers the response includes, without
          # moving updated_at.
          Rails.logger.info "Document #{document_id} unchanged (304 Not Modified)"
          record_unchanged_check!(document, **fetch_metadata(e.io))
        else
          Rails.logger.error "Failed to download document #{document_id}: #{e.message} (status: #{e.io&.status.inspect})"
        end
      rescue StandardError => e
        Rails.logger.error "Error processing document #{document_id}: #{e.message}"
      end
    end

    private

    def fetch_metadata(io)
      meta = io.respond_to?(:meta) ? io.meta : nil
      meta = {} unless meta.respond_to?(:[])
      last_modified = meta["last-modified"]

      {
        etag: meta["etag"],
        last_modified: last_modified.present? ? DateTime.parse(last_modified.to_s) : nil,
        content_length: meta["content-length"]&.to_i
      }
    end

    # update_columns skips updated_at. Only write headers the response actually sent.
    def record_unchanged_check!(document, etag:, last_modified:, content_length:)
      attributes = { fetched_at: Time.current }
      attributes[:etag] = etag if etag.present?
      attributes[:last_modified] = last_modified if last_modified.present?
      attributes[:content_length] = content_length unless content_length.nil?
      document.update_columns(attributes)
    end
  end
end
