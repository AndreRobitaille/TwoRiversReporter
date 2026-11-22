require "test_helper"
require "minitest/mock"
require "ostruct"
require "open-uri"

module Documents
  class TextVersionTest < ActiveJob::TestCase
    setup do
      @meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: Time.current,
        detail_page_url: "https://example.test/meeting")
      @document = @meeting.meeting_documents.create!(source_url: "https://example.test/minutes.pdf", document_type: "minutes_pdf")
      download("first synthetic PDF bytes")
      assert @document.reload.current_source_version, "Setup must retain the supplied artifact"
      clear_enqueued_jobs
    end

    test "pages and text retain their exact artifact across replacement and later reads" do
      analyze([ "First page: Alex Example voted no.", "Last page: implementation remains unknown." ])
      first = @document.reload.current_text_version
      assert_not_nil first
      assert_equal 2, first.page_count
      assert_equal [ 1, 2 ], first.pages.map { |page| page.fetch("page_number") }
      assert_includes first.extracted_text, "implementation remains unknown"
      assert_equal @document.current_source_version.id, first.meeting_document_version_id
      assert_equal "extracted", first.evidence_status

      download("corrected synthetic PDF bytes")
      assert_nil @document.reload.current_text_version
      analyze([ "Corrected first page: Alex Example voted yes.", "Corrected closing page: project deferred." ])

      latest = MeetingDocument.find(@document.id).current_text_version
      assert_not_equal first.id, latest.id
      assert_includes latest.extracted_text, "project deferred"
      assert_equal "First page: Alex Example voted no.", first.reload.pages.first.fetch("raw_text")
      assert_equal "first synthetic PDF bytes", first.meeting_document_version.file.download
    end

    test "installed PDF tools retain source pages including blank and closing pages" do
      bytes = File.binread(Rails.root.join("test/fixtures/files/synthetic_council_pages.pdf"))
      download(bytes)
      Ai::OpenAiService.stub :new, ->(*) { flunk "Native extraction must not dispatch AI" } do
        AnalyzePdfJob.perform_now(@document.id)
      end
      fresh = MeetingDocument.find(@document.id)
      version = fresh.current_text_version
      assert_equal 3, version.page_count
      assert_equal [ "SYNTHETIC opening action approved.", "", "SYNTHETIC closing action deferred." ],
        version.pages.map { |page| page.fetch("cleaned_text") }
      assert_equal version.extracted_text, fresh.extracted_text
      assert_equal version.extracted_text, fresh.extractions.order(:page_number).pluck(:cleaned_text).join(" ")
      assert_equal bytes, version.meeting_document_version.file.download
    end

    test "unchanged PDF analysis queues no additional downstream work or provider calls" do
      pages = [ "Synthetic minutes content with enough characters for text extraction." ]
      analyze(pages)
      first = @document.reload.current_text_version
      clear_enqueued_jobs
      assert_no_difference "MeetingDocumentTextVersion.count" do
        assert_no_enqueued_jobs { analyze(pages) }
      end
      assert_equal first.id, @document.reload.current_text_version.id
    end

    test "late PDF output cannot overwrite a newer artifact and its accepted pages" do
      with_method(Open3, :capture2e, ->(*) { [ "Pages: 1\n", success ] }) do
        with_method(Open3, :capture3, ->(*) {
          download("newer synthetic bytes")
          analyze([ "NEWER closing action: the project was deferred." ])
          [ "STALE closing action: the project was approved.\f", "", success ]
        }) { AnalyzePdfJob.perform_now(@document.id) }
      end
      fresh = MeetingDocument.find(@document.id)
      assert_includes fresh.extracted_text, "NEWER closing action"
      assert_equal fresh.current_text_version.extracted_text, fresh.extractions.order(:page_number).pluck(:cleaned_text).join(" ")
      assert_equal 1, MeetingDocumentTextVersion.count
    end

    test "failed extraction cannot erase previous pages or queue analysis" do
      analyze([ "Original known action: vote failed." ])
      first = @document.reload.current_text_version
      download("revised but unreadable bytes")
      clear_enqueued_jobs
      with_method(Open3, :capture2e, ->(*) { [ "Pages: 1\n", success ] }) do
        with_method(Open3, :capture3, ->(*) { [ "partial wrong text", "failure", OpenStruct.new(success?: false) ] }) do
          assert_no_enqueued_jobs { AnalyzePdfJob.perform_now(@document.id) }
        end
      end
      assert_equal "Original known action: vote failed.", @document.reload.extracted_text
      assert_equal [ "Original known action: vote failed." ], @document.extractions.pluck(:cleaned_text)
      assert_equal first.id, @document.latest_text_version_id
      assert_nil @document.current_text_version
    end

    test "blank pages and cleaned long tokens preserve complete page identity" do
      analyze([ "Opening action " + ("x" * 251), "", "Closing action: deferred.", "" ])
      version = @document.reload.current_text_version
      assert_equal [ 1, 2, 3, 4 ], version.pages.map { |page| page.fetch("page_number") }
      assert_equal "", version.pages.last.fetch("raw_text")
      assert_includes version.pages.first.fetch("raw_text"), "x" * 251
      assert_equal [ "Opening action", "", "Closing action: deferred.", "" ], @document.extractions.order(:page_number).pluck(:cleaned_text)
      assert_equal version.extracted_text, @document.extracted_text
    end

    test "OCR retains numeric page order and unchanged retries preserve accepted OCR" do
      analyze(Array.new(12, ""))
      pdf_version = @document.reload.current_text_version
      pages = (1..12).map { |number| "Synthetic page #{number}: recorded action #{number}." }
      ocr(pages)
      version = @document.reload.current_text_version
      assert_equal "ocr_v1", version.extractor_version
      assert_equal pages, version.pages.map { |page| page.fetch("raw_text") }
      assert_equal "completed", @document.ocr_status
      assert_equal 12, pdf_version.reload.pages.size
      assert_equal "", pdf_version.pages.last.fetch("raw_text")
      assert_not_equal pdf_version.id, version.id
      clear_enqueued_jobs
      assert_no_difference "MeetingDocumentTextVersion.count" do
        assert_no_enqueued_jobs do
          ocr(pages)
          analyze(Array.new(12, ""))
        end
      end
      assert_equal version.id, MeetingDocument.find(@document.id).current_text_version.id
    end

    test "replacement PDF does not inherit the prior artifact OCR completion" do
      ocr([ "Original recognized action: approved." ])
      old = @document.reload.current_text_version
      assert_equal "completed", @document.ocr_status
      download("Replacement PDF with a text layer")
      analyze([ "New text action: deferred." ])
      assert_nil @document.reload.ocr_status
      assert_equal "pdf_text_v1", @document.current_text_version.extractor_version
      assert_equal "ocr_v1", old.reload.extractor_version
    end

    test "an attachment inconsistent with the retained hash cannot acquire a text version" do
      @document.reload.file.attach(io: StringIO.new("untracked replacement"), filename: "mismatch.pdf")
      clear_enqueued_jobs
      assert_no_difference "MeetingDocumentTextVersion.count" do
        assert_no_enqueued_jobs { analyze([ "This must not be attached to the retained source." ]) }
      end
      assert_nil @document.reload.current_text_version
      assert_nil @document.extracted_text
    end

    test "missing final OCR page and failed recognition preserve previous evidence" do
      analyze([ "Original action one: approved.", "Original closing action: rejected." ])
      previous = @document.reload.current_text_version
      clear_enqueued_jobs
      assert_no_enqueued_jobs { ocr([ "Partial wrong output" ], expected_count: 2) }
      assert_equal previous.id, @document.reload.current_text_version.id
      assert_equal "failed", @document.ocr_status
      assert_no_enqueued_jobs { ocr([ "Partial page one", "Partial page two" ], failed_page: 2) }
      assert_equal previous.extracted_text, @document.reload.extracted_text
      assert_equal 2, @document.extractions.count
      assert_equal 1, MeetingDocumentTextVersion.count
    end

    test "late OCR output and failure cannot overwrite a newer completed extraction" do
      [ false, true ].each do |fail_old|
        download("Starting OCR revision #{fail_old}")
        ocr([ "STALE recognition" ], before_page: -> {
          download("Newer OCR revision #{fail_old}")
          ocr([ "NEWER recognized closing action #{fail_old}." ])
        }, failed_page: (1 if fail_old))
        fresh = MeetingDocument.find(@document.id)
        assert_equal "NEWER recognized closing action #{fail_old}.", fresh.extracted_text
        assert_equal "completed", fresh.ocr_status
        assert_equal fresh.extracted_text, fresh.current_text_version.extracted_text
      end
    end

    test "page persistence failure rolls back snapshot pointer and every projected page" do
      analyze([ "Original known action: approved." ])
      previous = @document.reload.current_text_version
      download("Corrected source with a failing page write")
      callback = -> { raise "synthetic database failure" if page_number == 2 }
      Extraction.set_callback(:create, :before, callback)
      begin
        assert_no_difference "MeetingDocumentTextVersion.count" do
          analyze([ "Corrected opening", "Corrected closing" ])
        end
      ensure
        Extraction.skip_callback(:create, :before, callback)
      end
      fresh = MeetingDocument.find(@document.id)
      assert_equal previous.id, fresh.latest_text_version_id
      assert_equal [ "Original known action: approved." ], fresh.extractions.pluck(:cleaned_text)
      assert_equal previous.extracted_text, fresh.extracted_text
      assert_nil fresh.current_text_version
    end

    test "document removal keeps extracted pages and original source bytes" do
      analyze([ "Preserved final action: no implementation documented." ])
      version = @document.reload.current_text_version
      @document.destroy!
      perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
      assert_equal "Preserved final action: no implementation documented.", version.reload.pages.first.fetch("raw_text")
      assert_equal "first synthetic PDF bytes", version.meeting_document_version.file.download
      assert_nil version.meeting_document_version.reload.meeting_document_id
    end

    test "retained text rejects edits and incomplete page sequences" do
      analyze([ "Immutable action one.", "Immutable action two." ])
      version = @document.reload.current_text_version
      assert_raises(ActiveRecord::ReadonlyAttributeError) { version.update!(extracted_text: "replacement") }
      incomplete = version.dup
      incomplete.fingerprint = "b" * 64
      incomplete.pages = version.pages.take(1)
      assert_not incomplete.valid?
      assert_includes incomplete.errors[:pages], "must preserve every page and the complete extracted text"
    end

    private

    def success
      OpenStruct.new(success?: true)
    end

    def download(bytes)
      with_method(URI, :open, ->(*) { StringIO.new(bytes) }) { DownloadJob.perform_now(@document.id) }
    end

    def analyze(pages)
      Ai::OpenAiService.stub :new, ->(*) { flunk "Text extraction must not dispatch AI" } do
        with_method(Open3, :capture2e, ->(*) { [ "Pages: #{pages.size}\n", success ] }) do
          with_method(Open3, :capture3, ->(*) { [ pages.join("\f") + "\f", "", success ] }) do
            AnalyzePdfJob.perform_now(@document.id)
          end
        end
      end
    end

    def ocr(pages, expected_count: pages.size, failed_page: nil, before_page: nil)
      job = OcrJob.new
      images = (1..pages.size).map { |number| "/tmp/synthetic2026/page-#{number}.png" }.sort
      with_method(job, :system, ->(*) { true }) do
        with_method(Dir, :glob, ->(*) { images }) do
          with_method(Open3, :capture2e, ->(*) { [ "Pages: #{expected_count}\n", success ] }) do
            with_method(Open3, :capture3, ->(_, path, *) {
              before_page&.call
              number = File.basename(path)[/page-(\d+)/, 1].to_i
              [ pages.fetch(number - 1), "", OpenStruct.new(success?: number != failed_page) ]
            }) { job.perform(@document.id) }
          end
        end
      end
    end

    def with_method(target, name, replacement)
      original = target.method(name)
      target.define_singleton_method(name) { |*args| replacement.call(*args) }
      yield
    ensure
      target.define_singleton_method(name, original)
    end
  end
end
