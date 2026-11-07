require "open-uri"
require "digest"

module Documents
  class DownloadJob < ApplicationJob
    queue_as :default

    def perform(document_id)
      document = MeetingDocument.find(document_id)
      return unless document.source_url.present?
      requested_state = download_state(document)

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

        changed = false
        document.with_lock do
          # Another fetch or source edit won while this request was in flight.
          return unless download_state(document) == requested_state

          changed = document.sha256 != sha
          filename = File.basename(URI.parse(document.source_url).path).presence || "document.pdf"
          if changed
            document.update!(sha256: sha, **metadata, fetched_at: Time.current)
            version = document.current_source_version
            if version
              # Reuse the archived blob when a publisher restores earlier bytes.
              document.file.attach(version.file.blob)
            else
              document.file.attach(io: downloaded_io, filename: filename)
            end
            MeetingDocumentVersion.capture!(document)
          else
            record_unchanged_check!(document, **metadata)
            # A legacy row may not yet have retained bytes. Capture the actual
            # response, without changing its current attachment or updated_at.
            MeetingDocumentVersion.capture!(document, file: { io: downloaded_io, filename: filename })
          end
        end

        # Retaining a previously unversioned artifact is deterministic work.
        # Only changed bytes enqueue the existing analysis pipeline.
        return unless changed

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
          document.with_lock do
            if download_state(document) == requested_state
              record_unchanged_check!(document, **fetch_metadata(e.io))
            end
          end
        else
          Rails.logger.error "Failed to download document #{document_id}: #{e.message} (status: #{e.io&.status.inspect})"
        end
      rescue StandardError => e
        Rails.logger.error "Error processing document #{document_id}: #{e.message}"
      ensure
        downloaded_io.close if downloaded_io.respond_to?(:close)
      end
    end

    private

    def download_state(document)
      document.attributes.slice("source_url", "document_type", "sha256", "fetched_at", "updated_at")
    end

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
