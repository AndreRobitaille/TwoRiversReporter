require "test_helper"
require "minitest/mock"
require "open-uri"

module Documents
  class SourceVersionRetentionTest < ActiveJob::TestCase
    setup do
      @sample = JSON.parse(file_fixture("council_evidence_sample.json").read)
      @meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: Time.zone.parse("2024-05-06 18:00"),
        detail_page_url: "https://example.test/meetings/may-6")
      @document = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/minutes.pdf")
    end

    test "replacement and later reads retain exact source bytes and separate dates" do
      download(@sample.fetch("minutes_v1"))
      original = @document.reload.current_source_version
      assert_equal @sample.fetch("minutes_v1"), original.file.download
      assert_equal @document.sha256, original.sha256
      assert_equal @meeting.starts_at, original.meeting_starts_at
      assert_equal @document.fetched_at, original.retrieved_at
      assert_equal Time.utc(2024, 5, 8), original.source_last_modified
      assert_nil original.published_at
      assert_equal "collected", original.evidence_status
      assert_equal "download_sha256_v1", original.capture_method

      travel 1.hour do
        download(@sample.fetch("minutes_v2"))
      end

      current = MeetingDocument.find(@document.id).current_source_version
      perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
      assert_not_equal original.id, current.id
      assert_equal 2, @document.source_versions.count
      assert_equal @sample.fetch("minutes_v2"), current.file.download
      assert_equal @sample.fetch("minutes_v1"), MeetingDocumentVersion.find(original.id).file.download
      assert_equal "collected", current.evidence_status
      assert_not original.reload.current?
      assert current.current?
      assert_equal 2, enqueued_jobs.count { |job| job[:job] == AnalyzePdfJob }
    end

    test "an unchanged legacy download gains retained evidence without claiming a new content update" do
      @document.update!(sha256: Digest::SHA256.hexdigest(@sample.fetch("minutes_v1")))
      updated_at = @document.updated_at
      travel 1.hour do
        assert_no_enqueued_jobs { download(@sample.fetch("minutes_v1")) }
      end
      assert_equal updated_at, @document.reload.updated_at
      assert_equal @sample.fetch("minutes_v1"), @document.current_source_version.file.download
    end

    test "unchanged responses reuse the version and enqueue no additional analysis or AI" do
      download(@sample.fetch("minutes_v1"))
      original = @document.reload.current_source_version
      updated_at = @document.updated_at
      clear_enqueued_jobs

      travel 1.hour do
        assert_no_difference [ "MeetingDocumentVersion.count", "ActiveStorage::Blob.count" ] do
          assert_no_enqueued_jobs do
            download(@sample.fetch("minutes_v1"))
            http_error("304")
          end
        end
      end

      assert_equal original.id, @document.reload.current_source_version.id
      assert_equal updated_at, @document.updated_at
      assert_operator @document.fetched_at, :>, original.retrieved_at
    end

    test "reversion reuses retained bytes while a different URL is a distinct source version" do
      download(@sample.fetch("minutes_v1"))
      original = @document.reload.current_source_version
      download(@sample.fetch("minutes_v2"))
      assert_no_difference [ "MeetingDocumentVersion.count", "ActiveStorage::Blob.count" ] do
        download(@sample.fetch("minutes_v1"))
      end
      assert_equal original.id, @document.reload.current_source_version.id
      assert_equal original.file.blob_id, @document.file.blob_id

      @document.update!(source_url: "https://example.test/replacement.pdf")
      assert_nil @document.current_source_version
      download(@sample.fetch("minutes_v1"))
      assert_equal 3, @document.source_versions.count
      assert_not_equal original.id, @document.reload.current_source_version.id
      assert_equal "https://example.test/minutes.pdf", original.reload.source_url
    end

    test "failed fetch and document removal preserve retained evidence without substitution" do
      download(@sample.fetch("minutes_v1"))
      original = @document.reload.current_source_version
      clear_enqueued_jobs
      assert_no_enqueued_jobs { http_error("404") }
      assert_equal original.id, @document.reload.current_source_version.id

      @document.destroy!
      # Exercise the actual queued old-attachment purge after replacement/removal.
      perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
      assert MeetingDocumentVersion.exists?(original.id), "Removing a document must retain its evidence version"
      retained = MeetingDocumentVersion.find(original.id)
      assert_nil retained.meeting_document_id
      assert_equal @document.id, retained.original_document_id
      assert_equal @sample.fetch("minutes_v1"), retained.file.download
      assert_not retained.current?
    end

    test "a delayed successful response cannot overwrite a newer download" do
      download(@sample.fetch("minutes_v1"))
      clear_enqueued_jobs

      with_uri_open ->(*) {
        download(@sample.fetch("minutes_v2"))
        response("stale competing source bytes")
      } do
        DownloadJob.perform_now(@document.id)
      end

      assert_equal @sample.fetch("minutes_v2"), @document.reload.file.download
      assert_equal 2, @document.source_versions.count
      assert_equal 1, enqueued_jobs.count { |job| job[:job] == AnalyzePdfJob }
    end

    test "a delayed 304 cannot change metadata from a newer download" do
      download(@sample.fetch("minutes_v1"))
      newer_check = nil
      with_uri_open ->(*) {
        travel 1.hour do
          download(@sample.fetch("minutes_v2"))
          newer_check = @document.reload.fetched_at
        end
        raise_http_error("304")
      } do
        DownloadJob.perform_now(@document.id)
      end
      assert_equal newer_check, @document.reload.fetched_at
      assert_equal @sample.fetch("minutes_v2"), @document.current_source_version.file.download
    end

    test "version persistence failure rolls back the current file and does not enqueue analysis" do
      download(@sample.fetch("minutes_v1"))
      original = @document.reload.current_source_version
      clear_enqueued_jobs
      MeetingDocumentVersion.stub :capture!, ->(*) { raise ActiveRecord::RecordInvalid } do
        assert_no_difference "ActiveStorage::Blob.count" do
          assert_no_enqueued_jobs { download(@sample.fetch("minutes_v2")) }
        end
      end
      assert_equal original.sha256, @document.reload.sha256
      assert_equal original.file.blob_id, @document.file.blob_id
      assert_equal original.id, @document.current_source_version.id
    end

    test "failed blob upload cannot publish a version or advance the current source" do
      download(@sample.fetch("minutes_v1"))
      original = @document.reload.current_source_version
      clear_enqueued_jobs
      ActiveStorage::Blob.service.stub :upload, ->(*) { raise IOError, "synthetic storage outage" } do
        assert_no_difference "MeetingDocumentVersion.count" do
          assert_no_enqueued_jobs { download(@sample.fetch("minutes_v2")) }
        end
      end
      assert_equal original.sha256, @document.reload.sha256
      assert_equal original.id, @document.current_source_version.id
      assert_equal @sample.fetch("minutes_v1"), @document.file.download

      download(@sample.fetch("minutes_v2"))
      assert_equal @sample.fetch("minutes_v2"), @document.reload.current_source_version.file.download
    end

    private

    def download(text)
      Ai::OpenAiService.stub :new, ->(*) { flunk "Artifact retention must not call AI" } do
        with_uri_open(->(*) { response(text) }) { DownloadJob.perform_now(@document.id) }
      end
    end

    def response(text)
      StringIO.new(text).tap do |io|
        io.define_singleton_method(:meta) { { "last-modified" => "Wed, 08 May 2024 00:00:00 GMT" } }
      end
    end

    def http_error(status)
      with_uri_open(->(*) { raise_http_error(status) }) { DownloadJob.perform_now(@document.id) }
    end

    # Minitest's method aliases do not support nesting the same stub. Nested
    # delivery represents a second worker completing during the first request.
    def with_uri_open(replacement)
      original = URI.method(:open)
      URI.define_singleton_method(:open) { |*args| replacement.call(*args) }
      yield
    ensure
      URI.define_singleton_method(:open, original)
    end

    def raise_http_error(status)
      io = StringIO.new("")
      io.define_singleton_method(:status) { [ status, "Synthetic HTTP response" ] }
      raise OpenURI::HTTPError.new(status, io)
    end
  end
end
