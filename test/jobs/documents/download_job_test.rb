require "test_helper"
require "open-uri"

module Documents
  class DownloadJobTest < ActiveJob::TestCase
    include ActiveJob::TestHelper

    def setup
      @meeting = Meeting.create!(
        body_name: "Test Body",
        detail_page_url: "http://example.com/meeting",
        starts_at: Time.current
      )
      @document = MeetingDocument.create!(
        meeting: @meeting,
        source_url: "http://example.com/doc.pdf",
        document_type: "agenda_pdf",
        sha256: Digest::SHA256.hexdigest("old content"),
        etag: "old_etag",
        last_modified: 1.day.ago,
        fetched_at: 1.day.ago
      )
    end

    def with_uri_open_stub(stub_proc)
      original_open = URI.method(:open)
      URI.define_singleton_method(:open, stub_proc)
      yield
    ensure
      URI.define_singleton_method(:open, original_open)
    end

    test "handles 304 Not Modified" do
      headers_checked = false

      stub = proc do |url, headers|
        if headers["If-None-Match"] == "old_etag"
           headers_checked = true
        end

        io_mock = Object.new
        def io_mock.status; [ "304", "Not Modified" ]; end

        raise OpenURI::HTTPError.new("304 Not Modified", io_mock)
      end

      with_uri_open_stub(stub) do
        assert_no_performed_jobs do
          DownloadJob.perform_now(@document.id)
        end
      end

      assert headers_checked, "Headers were not passed correctly"

      @document.reload
      assert_operator @document.fetched_at, :>, 1.minute.ago
      # SHA should remain unchanged
      assert_equal Digest::SHA256.hexdigest("old content"), @document.sha256
    end

    test "handles unchanged content by SHA" do
      stub = proc do |url, headers|
        content = "old content"
        response = StringIO.new(content)
        def response.meta
          { "etag" => "new_etag", "last-modified" => Time.current.httpdate }
        end
        response
      end

      with_uri_open_stub(stub) do
        assert_no_performed_jobs do
          DownloadJob.perform_now(@document.id)
        end
      end

      @document.reload
      # Metadata updated
      assert_equal "new_etag", @document.etag
      # But content still same
      assert_equal Digest::SHA256.hexdigest("old content"), @document.sha256
    end

    test "handles changed content" do
      stub = proc do |url, headers|
        content = "new content"
        response = StringIO.new(content)
        def response.meta
          { "etag" => "newer_etag", "last-modified" => Time.current.httpdate }
        end
        response
      end

      with_uri_open_stub(stub) do
        assert_enqueued_with(job: Documents::AnalyzePdfJob) do
          DownloadJob.perform_now(@document.id)
        end
      end

      @document.reload
      assert_equal Digest::SHA256.hexdigest("new content"), @document.sha256
      assert_equal "newer_etag", @document.etag
      assert @document.file.attached?
      assert_equal "new content", @document.file.download
    end
  end
end
