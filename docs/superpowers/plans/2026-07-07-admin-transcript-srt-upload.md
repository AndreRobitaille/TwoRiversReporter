# Admin Transcript SRT Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional `.srt` upload to the admin transcript import form that overrides YouTube caption download while keeping the YouTube URL as provenance.

**Architecture:** Store the optional uploaded SRT on `TranscriptImport` with Active Storage, then branch inside `Admin::TranscriptImportWorkflowJob`. A new `Documents::UploadedTranscriptImporter` service owns uploaded SRT parsing and transcript `MeetingDocument` creation so the job remains orchestration-only.

**Tech Stack:** Rails, Active Storage, Minitest, Active Job test helpers, server-rendered ERB, minimal inline JavaScript.

---

## File Structure

- Modify `app/models/transcript_import.rb`
  - Add `has_one_attached :srt_file`.
- Modify `app/controllers/admin/transcript_imports_controller.rb`
  - Permit `:srt_file`.
  - Validate optional SRT uploads before queueing.
  - Attach the uploaded file to the queued `TranscriptImport`.
- Modify `app/views/admin/transcript_imports/show.html.erb`
  - Add optional file input, explanatory copy, remove-file button, multipart form encoding, and small JavaScript for clearing the selected file.
- Create `app/services/documents/uploaded_transcript_importer.rb`
  - Read uploaded SRT, parse transcript text, create the transcript `MeetingDocument`, and attach the uploaded SRT content.
- Modify `app/services/documents/transcript_downloader.rb`
  - Expose the existing SRT text parsing logic as a class method so uploaded and downloaded transcripts parse identically.
- Modify `app/jobs/admin/transcript_import_workflow_job.rb`
  - Use uploaded SRT service when `transcript_import.srt_file.attached?`; otherwise keep existing downloader path.
- Modify `test/controllers/admin/transcript_imports_controller_test.rb`
  - Cover UI, upload acceptance, upload validation, and selected-field preservation on upload validation failure.
- Create `test/services/documents/uploaded_transcript_importer_test.rb`
  - Cover uploaded SRT storage, replacement behavior, invalid blank transcripts, and attach failure cleanup.
- Modify `test/jobs/admin/transcript_import_workflow_job_test.rb`
  - Cover uploaded SRT workflow branch and logging.
- Modify `test/services/documents/transcript_downloader_test.rb`
  - Add coverage for the shared SRT parser class method.

---

### Task 1: Add uploaded SRT model and controller acceptance

**Files:**
- Modify: `app/models/transcript_import.rb`
- Modify: `app/controllers/admin/transcript_imports_controller.rb`
- Modify: `test/controllers/admin/transcript_imports_controller_test.rb`

- [ ] **Step 1: Write failing controller/model tests**

Add these tests after `test "create enqueues workflow and creates queued record"` in `test/controllers/admin/transcript_imports_controller_test.rb`:

```ruby
  test "create attaches uploaded srt and enqueues workflow" do
    sign_in_as_admin

    upload = uploaded_file(sample_srt, filename: "manual-transcript.srt", content_type: "text/srt")

    assert_enqueued_with(job: Admin::TranscriptImportWorkflowJob) do
      post admin_transcript_imports_path, params: {
        transcript_import: {
          meeting_id: @meeting.id,
          youtube_url: youtube_url,
          srt_file: upload
        }
      }
    end

    transcript_import = TranscriptImport.last
    assert_redirected_to admin_transcript_imports_path
    assert_match(/Transcript import workflow queued/i, flash[:notice])
    assert transcript_import.srt_file.attached?
    assert_equal "manual-transcript.srt", transcript_import.srt_file.filename.to_s
  end

  test "create rejects non srt upload and preserves meeting and url" do
    sign_in_as_admin

    upload = uploaded_file("not an srt", filename: "notes.txt", content_type: "text/plain")

    assert_no_enqueued_jobs do
      post admin_transcript_imports_path, params: {
        transcript_import: {
          meeting_id: @meeting.id,
          youtube_url: youtube_url,
          srt_file: upload
        }
      }
    end

    assert_redirected_to admin_transcript_imports_path(meeting_id: @meeting.id, youtube_url: youtube_url)
    assert_match(/Upload an SRT file/i, flash[:alert])
    assert_equal 0, TranscriptImport.count
  end

  test "create rejects empty srt upload" do
    sign_in_as_admin

    upload = uploaded_file("", filename: "empty.srt", content_type: "text/srt")

    assert_no_enqueued_jobs do
      post admin_transcript_imports_path, params: {
        transcript_import: {
          meeting_id: @meeting.id,
          youtube_url: youtube_url,
          srt_file: upload
        }
      }
    end

    assert_redirected_to admin_transcript_imports_path(meeting_id: @meeting.id, youtube_url: youtube_url)
    assert_match(/Upload an SRT file/i, flash[:alert])
    assert_equal 0, TranscriptImport.count
  end
```

Add this helper before `def youtube_url` in the private section:

```ruby
  def uploaded_file(content, filename:, content_type:)
    tempfile = Tempfile.new([ File.basename(filename, ".srt"), File.extname(filename) ])
    tempfile.binmode
    tempfile.write(content)
    tempfile.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: filename,
      type: content_type
    )
  end

  def sample_srt
    <<~SRT
      1
      00:00:01,000 --> 00:00:03,000
      Welcome to the uploaded transcript.
    SRT
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
bin/rails test test/controllers/admin/transcript_imports_controller_test.rb
```

Expected: failures mentioning `srt_file` is not permitted or `TranscriptImport` does not respond to `srt_file`.

- [ ] **Step 3: Add model attachment and controller upload handling**

In `app/models/transcript_import.rb`, add the attachment after the associations:

```ruby
  has_one_attached :srt_file
```

In `app/controllers/admin/transcript_imports_controller.rb`, replace `create` and `transcript_import_params` with:

```ruby
    def create
      meeting = Meeting.find_by(id: transcript_import_params[:meeting_id])
      unless meeting
        redirect_to admin_transcript_imports_path, alert: "Choose a valid meeting."
        return
      end

      youtube_url = transcript_import_params[:youtube_url].to_s.strip
      unless Documents::TranscriptDownloader.valid_url?(youtube_url)
        redirect_to admin_transcript_imports_path(meeting_id: meeting.id, youtube_url: youtube_url), alert: "Enter a valid YouTube watch URL."
        return
      end

      srt_file = transcript_import_params[:srt_file]
      unless valid_srt_upload?(srt_file)
        redirect_to admin_transcript_imports_path(meeting_id: meeting.id, youtube_url: youtube_url), alert: "Upload an SRT file, or remove the selected file before importing."
        return
      end

      transcript_import = TranscriptImport.create!(meeting: meeting, youtube_url: youtube_url, status: "queued")
      transcript_import.srt_file.attach(srt_file) if srt_file.present?
      Admin::TranscriptImportWorkflowJob.perform_later(transcript_import.id)

      redirect_to admin_transcript_imports_path, notice: "Transcript import workflow queued."
    end
```

Add these private helper methods above `transcript_import_params`:

```ruby
    def valid_srt_upload?(upload)
      return true if upload.blank?
      return false unless upload.respond_to?(:original_filename)
      return false unless File.extname(upload.original_filename.to_s).casecmp(".srt").zero?
      return false if upload.respond_to?(:size) && upload.size.to_i <= 0

      allowed_content_types = %w[text/srt application/x-subrip text/plain application/octet-stream]
      upload.content_type.blank? || allowed_content_types.include?(upload.content_type)
    end
```

Replace `transcript_import_params` with:

```ruby
    def transcript_import_params
      params.fetch(:transcript_import, {}).permit(:meeting_id, :youtube_url, :srt_file)
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
bin/rails test test/controllers/admin/transcript_imports_controller_test.rb
```

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add app/models/transcript_import.rb app/controllers/admin/transcript_imports_controller.rb test/controllers/admin/transcript_imports_controller_test.rb
git commit -m "feat: accept transcript srt uploads"
```

---

### Task 2: Add shared SRT parsing and uploaded transcript importer

**Files:**
- Modify: `app/services/documents/transcript_downloader.rb`
- Create: `app/services/documents/uploaded_transcript_importer.rb`
- Modify: `test/services/documents/transcript_downloader_test.rb`
- Create: `test/services/documents/uploaded_transcript_importer_test.rb`

- [ ] **Step 1: Write failing shared parser test**

Add this test near the top of `test/services/documents/transcript_downloader_test.rb`, after `def setup`:

```ruby
    test "parse_srt removes sequence numbers and timestamps" do
      plain_text = TranscriptDownloader.parse_srt(SAMPLE_SRT)

      assert_includes plain_text, "Welcome to the city council meeting."
      assert_includes plain_text, "Tonight we will discuss the budget proposal."
      assert_not_includes plain_text, "00:00:01,000"
      assert_not_match(/^1$/, plain_text)
    end
```

- [ ] **Step 2: Write failing uploaded importer tests**

Create `test/services/documents/uploaded_transcript_importer_test.rb` with:

```ruby
require "test_helper"

module Documents
  class UploadedTranscriptImporterTest < ActiveSupport::TestCase
    SAMPLE_SRT = <<~SRT
      1
      00:00:01,000 --> 00:00:03,000
      Welcome to the uploaded transcript.

      2
      00:00:04,000 --> 00:00:06,000
      The council discussed utility rates.
    SRT

    def setup
      @meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.zone.local(2026, 3, 15, 18, 0, 0), status: "held", detail_page_url: "http://example.com/meetings/uploaded-transcript-test-#{SecureRandom.hex(4)}")
      @video_url = "https://www.youtube.com/watch?v=abc123"
    end

    test "creates transcript document from uploaded srt attachment" do
      transcript_import = build_transcript_import_with_srt(SAMPLE_SRT, filename: "manual.srt")

      result = UploadedTranscriptImporter.new(
        meeting: @meeting,
        youtube_url: @video_url,
        srt_file: transcript_import.srt_file
      ).import

      assert_predicate result, :created?
      assert_equal "uploaded_srt", result.source

      document = result.meeting_document
      assert_equal @meeting, document.meeting
      assert_equal "transcript", document.document_type
      assert_equal @video_url, document.source_url
      assert_equal "uploaded_transcript", document.text_quality
      assert_includes document.extracted_text, "Welcome to the uploaded transcript."
      assert_includes document.extracted_text, "The council discussed utility rates."
      assert_not_includes document.extracted_text, "00:00:01,000"
      assert_equal document.extracted_text.length, document.text_chars
      assert document.file.attached?
      assert_equal "manual.srt", document.file.filename.to_s
    end

    test "replaces existing transcript document" do
      stale = @meeting.meeting_documents.create!(document_type: "transcript", source_url: @video_url, text_quality: "auto_transcribed", extracted_text: "stale", text_chars: 5)
      stale.file.attach(io: StringIO.new("stale"), filename: "stale.srt", content_type: "text/srt")
      transcript_import = build_transcript_import_with_srt(SAMPLE_SRT)

      result = UploadedTranscriptImporter.new(
        meeting: @meeting,
        youtube_url: @video_url,
        srt_file: transcript_import.srt_file
      ).import

      assert_predicate result, :created?
      assert_not MeetingDocument.exists?(stale.id)
      assert_equal 1, @meeting.meeting_documents.where(document_type: "transcript").count
    end

    test "raises import error when uploaded srt has no transcript text" do
      transcript_import = build_transcript_import_with_srt("1\n00:00:01,000 --> 00:00:03,000\n")

      error = assert_raises(UploadedTranscriptImporter::ImportError) do
        UploadedTranscriptImporter.new(
          meeting: @meeting,
          youtube_url: @video_url,
          srt_file: transcript_import.srt_file
        ).import
      end

      assert_match(/did not contain transcript text/i, error.message)
      assert_equal 0, @meeting.meeting_documents.where(document_type: "transcript").count
    end

    test "removes created record if attaching stored transcript fails" do
      transcript_import = build_transcript_import_with_srt(SAMPLE_SRT)
      importer = UploadedTranscriptImporter.new(
        meeting: @meeting,
        youtube_url: @video_url,
        srt_file: transcript_import.srt_file
      )

      importer.stub :attach_transcript_file, ->(*) { raise StandardError, "attach failed" } do
        assert_raises(StandardError) { importer.import }
      end

      assert_equal 0, @meeting.meeting_documents.where(document_type: "transcript").count
    end

    private

    def build_transcript_import_with_srt(content, filename: "uploaded.srt")
      TranscriptImport.create!(meeting: @meeting, youtube_url: @video_url, status: "queued").tap do |transcript_import|
        transcript_import.srt_file.attach(io: StringIO.new(content), filename: filename, content_type: "text/srt")
      end
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
bin/rails test test/services/documents/transcript_downloader_test.rb test/services/documents/uploaded_transcript_importer_test.rb
```

Expected: failures mentioning `TranscriptDownloader.parse_srt` and `Documents::UploadedTranscriptImporter` are undefined.

- [ ] **Step 4: Expose shared SRT parser**

In `app/services/documents/transcript_downloader.rb`, add this class method after `self.precheck` and before `self.run_yt_dlp`:

```ruby
    def self.parse_srt(srt_content)
      srt_content
        .to_s
        .gsub(/^\d+\s*$/, "")
        .gsub(/^\d{2}:\d{2}:\d{2},\d{3}\s*-->.*$/, "")
        .gsub(/\n{3,}/, "\n\n")
        .strip
    end
```

Replace the private instance `parse_srt` method with:

```ruby
    def parse_srt(srt_content)
      self.class.parse_srt(srt_content)
    end
```

- [ ] **Step 5: Add uploaded transcript importer service**

Create `app/services/documents/uploaded_transcript_importer.rb` with:

```ruby
module Documents
  class UploadedTranscriptImporter
    ImportError = Class.new(StandardError)

    Result = Struct.new(:status, :meeting_document, :source, keyword_init: true) do
      def created?
        status == "created"
      end

      def reused?
        status == "reused"
      end
    end

    def initialize(meeting:, youtube_url:, srt_file:)
      @meeting = meeting
      @youtube_url = youtube_url
      @srt_file = srt_file
    end

    def import
      raise ImportError, "Uploaded SRT file is missing" unless @srt_file&.attached?

      @meeting.with_lock do
        srt_content = @srt_file.download
        plain_text = TranscriptDownloader.parse_srt(srt_content)
        raise ImportError, "Uploaded SRT did not contain transcript text" if plain_text.blank?

        @meeting.meeting_documents.where(document_type: "transcript").destroy_all

        document = @meeting.meeting_documents.create!(
          document_type: "transcript",
          source_url: @youtube_url,
          extracted_text: plain_text,
          text_quality: "uploaded_transcript",
          text_chars: plain_text.length,
          fetched_at: Time.current
        )

        begin
          attach_transcript_file(document, srt_content)
        rescue StandardError
          document.destroy!
          raise
        end

        Result.new(status: "created", meeting_document: document, source: "uploaded_srt")
      end
    end

    private

    def attach_transcript_file(document, srt_content)
      document.file.attach(
        io: StringIO.new(srt_content),
        filename: @srt_file.filename.to_s.presence || "uploaded-transcript-#{@meeting.id}.srt",
        content_type: "text/srt"
      )
    end
  end
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run:

```bash
bin/rails test test/services/documents/transcript_downloader_test.rb test/services/documents/uploaded_transcript_importer_test.rb
```

Expected: PASS.

- [ ] **Step 7: Commit Task 2**

Run:

```bash
git add app/services/documents/transcript_downloader.rb app/services/documents/uploaded_transcript_importer.rb test/services/documents/transcript_downloader_test.rb test/services/documents/uploaded_transcript_importer_test.rb
git commit -m "feat: import uploaded transcript srt files"
```

---

### Task 3: Branch workflow job for uploaded SRT files

**Files:**
- Modify: `app/jobs/admin/transcript_import_workflow_job.rb`
- Modify: `test/jobs/admin/transcript_import_workflow_job_test.rb`

- [ ] **Step 1: Write failing job test for uploaded SRT path**

Add this test after `test "successfully downloads transcript, summarizes, prunes, reanalyzes, and completes"` in `test/jobs/admin/transcript_import_workflow_job_test.rb`:

```ruby
    test "uses uploaded srt importer when an srt file is attached" do
      @transcript_import.srt_file.attach(
        io: StringIO.new("1\n00:00:01,000 --> 00:00:03,000\nUploaded transcript text."),
        filename: "manual.srt",
        content_type: "text/srt"
      )
      document = MeetingDocument.create!(meeting: @meeting, document_type: "transcript", source_url: @transcript_import.youtube_url, extracted_text: "Uploaded transcript text.", text_quality: "uploaded_transcript", text_chars: 25)
      upload_result = Documents::UploadedTranscriptImporter::Result.new(status: "created", meeting_document: document, source: "uploaded_srt")

      importer = Minitest::Mock.new
      importer.expect :import, upload_result

      reanalysis_result = ::Topics::MeetingReanalysisService::Result.new(meeting: @meeting, before_topic_ids: [], after_topic_ids: [], affected_topic_ids: [], selector_ids: [], wire_ids: [])
      reanalysis_service = Minitest::Mock.new
      reanalysis_service.expect :call, reanalysis_result

      Rails.logger.stub :error, nil do
        Documents::TranscriptDownloader.stub :new, ->(*) { flunk "should not use YouTube downloader when an SRT is uploaded" } do
          Documents::UploadedTranscriptImporter.stub :new, ->(meeting:, youtube_url:, srt_file:) {
            assert_equal @meeting, meeting
            assert_equal @transcript_import.youtube_url, youtube_url
            assert_equal @transcript_import.srt_file, srt_file
            importer
          } do
            SummarizeMeetingJob.stub :perform_now, ->(meeting_id, mode: :full, enqueue_followups: true) {
              assert_equal @meeting.id, meeting_id
              assert_equal :full, mode
              assert_equal false, enqueue_followups
            } do
              PruneHollowAppearancesJob.stub :perform_now, ->(meeting_id) { assert_equal @meeting.id, meeting_id } do
                ::Topics::MeetingReanalysisService.stub :new, ->(meeting_id) {
                  assert_equal @meeting.id, meeting_id
                  reanalysis_service
                } do
                  Admin::TranscriptImportWorkflowJob.perform_now(@transcript_import.id)
                end
              end
            end
          end
        end
      end

      importer.verify
      reanalysis_service.verify

      @transcript_import.reload
      assert_equal "completed", @transcript_import.status
      assert_equal document.id, @transcript_import.meeting_document_id

      import_log = @transcript_import.step_logs.find { |entry| entry["step"] == "download_transcript" }
      assert_equal "Transcript uploaded", import_log["message"]
      assert_equal "created", import_log.dig("metadata", "status")
      assert_equal "uploaded_srt", import_log.dig("metadata", "source")
      assert_equal document.id, import_log.dig("metadata", "meeting_document_id")
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bin/rails test test/jobs/admin/transcript_import_workflow_job_test.rb
```

Expected: failure because the job still calls `Documents::TranscriptDownloader` for uploaded SRT imports.

- [ ] **Step 3: Add workflow branching**

In `app/jobs/admin/transcript_import_workflow_job.rb`, replace lines that create `downloader_result` and log `Transcript reused/downloaded` with this block:

```ruby
      transcript_result = import_transcript(transcript_import)

      meeting_document = transcript_result.meeting_document
      log_and_append(transcript_import,
        step: "download_transcript",
        message: transcript_log_message(transcript_result),
        metadata: {
          status: transcript_result.status,
          source: transcript_source(transcript_result),
          meeting_document_id: meeting_document&.id,
          text_chars: meeting_document&.text_chars
        }
      )
```

Add these private methods before `log_failure`:

```ruby
    def import_transcript(transcript_import)
      if transcript_import.srt_file.attached?
        Documents::UploadedTranscriptImporter
          .new(
            meeting: transcript_import.meeting,
            youtube_url: transcript_import.youtube_url,
            srt_file: transcript_import.srt_file
          )
          .import
      else
        Documents::TranscriptDownloader
          .new(meeting: transcript_import.meeting, video_url: transcript_import.youtube_url)
          .download_and_store
      end
    end

    def transcript_log_message(transcript_result)
      return "Transcript uploaded" if transcript_source(transcript_result) == "uploaded_srt"

      transcript_result.reused? ? "Transcript reused" : "Transcript downloaded"
    end

    def transcript_source(transcript_result)
      transcript_result.respond_to?(:source) && transcript_result.source.present? ? transcript_result.source : "youtube_captions"
    end
```

- [ ] **Step 4: Run job tests to verify they pass**

Run:

```bash
bin/rails test test/jobs/admin/transcript_import_workflow_job_test.rb
```

Expected: PASS.

- [ ] **Step 5: Commit Task 3**

Run:

```bash
git add app/jobs/admin/transcript_import_workflow_job.rb test/jobs/admin/transcript_import_workflow_job_test.rb
git commit -m "feat: route transcript workflow through uploaded srt"
```

---

### Task 4: Add admin form upload UI and remove button

**Files:**
- Modify: `app/views/admin/transcript_imports/show.html.erb`
- Modify: `test/controllers/admin/transcript_imports_controller_test.rb`

- [ ] **Step 1: Update failing UI assertions**

In `test/controllers/admin/transcript_imports_controller_test.rb`, inside `test "authenticated admin can see transcript imports page"`, add these assertions inside the existing `assert_select "form..."` block after the YouTube URL input assertion:

```ruby
      assert_select "input[type=file][name='transcript_import[srt_file]'][accept='.srt,text/srt,application/x-subrip,text/plain']"
      assert_select "p", text: /If an SRT is uploaded, it will be used instead of YouTube captions/i
      assert_select "button[type=button][data-transcript-import-remove-file]", text: "Remove file"
```

Also change the form assertion from:

```ruby
    assert_select "form[action=?][method=post]", admin_transcript_imports_path do
```

to:

```ruby
    assert_select "form[action=?][method=post][enctype='multipart/form-data']", admin_transcript_imports_path do
```

- [ ] **Step 2: Run controller test to verify it fails**

Run:

```bash
bin/rails test test/controllers/admin/transcript_imports_controller_test.rb
```

Expected: failure because the form lacks multipart encoding, file input, note, and remove button.

- [ ] **Step 3: Add upload UI and remove-file JavaScript**

In `app/views/admin/transcript_imports/show.html.erb`, change the `form_with` opening tag to include multipart:

```erb
      <%= form_with url: admin_transcript_imports_path, method: :post, scope: :transcript_import, local: true, html: { class: "transcript-imports-form", multipart: true } do |form| %>
```

Add this block after the YouTube URL control and before `.transcript-imports-form__actions`:

```erb
        <div class="transcript-imports-form__control" data-transcript-import-file-control>
          <%= form.label :srt_file, "SRT transcript file (optional)", class: "form-label" %>
          <%= form.file_field :srt_file, accept: ".srt,text/srt,application/x-subrip,text/plain", class: "form-input", data: { transcript_import_file: true } %>
          <p class="form-help">If an SRT is uploaded, it will be used instead of YouTube captions. The YouTube URL is still saved as the source video.</p>
          <button type="button" class="btn btn--secondary" data-transcript-import-remove-file hidden>Remove file</button>
        </div>
```

In the existing `<script>` block, after the meeting filter setup code and before `})();`, add:

```javascript
    const fileInput = document.querySelector("[data-transcript-import-file]");
    const removeFileButton = document.querySelector("[data-transcript-import-remove-file]");

    if (fileInput && removeFileButton) {
      const syncRemoveFileButton = () => {
        removeFileButton.hidden = !fileInput.value;
      };

      fileInput.addEventListener("change", syncRemoveFileButton);
      removeFileButton.addEventListener("click", () => {
        fileInput.value = "";
        syncRemoveFileButton();
        fileInput.focus();
      });

      syncRemoveFileButton();
    }
```

- [ ] **Step 4: Run controller test to verify it passes**

Run:

```bash
bin/rails test test/controllers/admin/transcript_imports_controller_test.rb
```

Expected: PASS.

- [ ] **Step 5: Commit Task 4**

Run:

```bash
git add app/views/admin/transcript_imports/show.html.erb test/controllers/admin/transcript_imports_controller_test.rb
git commit -m "feat: add transcript srt upload form control"
```

---

### Task 5: Final verification and cleanup

**Files:**
- Review all changed files from Tasks 1-4.

- [ ] **Step 1: Run focused transcript import tests**

Run:

```bash
bin/rails test test/controllers/admin/transcript_imports_controller_test.rb test/jobs/admin/transcript_import_workflow_job_test.rb test/services/documents/transcript_downloader_test.rb test/services/documents/uploaded_transcript_importer_test.rb test/models/transcript_import_test.rb
```

Expected: PASS.

- [ ] **Step 2: Run style check on changed Ruby files**

Run:

```bash
bin/rubocop app/models/transcript_import.rb app/controllers/admin/transcript_imports_controller.rb app/jobs/admin/transcript_import_workflow_job.rb app/services/documents/transcript_downloader.rb app/services/documents/uploaded_transcript_importer.rb test/controllers/admin/transcript_imports_controller_test.rb test/jobs/admin/transcript_import_workflow_job_test.rb test/services/documents/transcript_downloader_test.rb test/services/documents/uploaded_transcript_importer_test.rb
```

Expected: no offenses.

- [ ] **Step 3: Run full test suite if focused tests and RuboCop pass**

Run:

```bash
bin/rails test
```

Expected: PASS.

- [ ] **Step 4: Inspect diff for accidental broad changes**

Run:

```bash
git status --short
git diff --stat HEAD~4..HEAD
git diff HEAD~4..HEAD -- app/models/transcript_import.rb app/controllers/admin/transcript_imports_controller.rb app/jobs/admin/transcript_import_workflow_job.rb app/services/documents/transcript_downloader.rb app/services/documents/uploaded_transcript_importer.rb app/views/admin/transcript_imports/show.html.erb test/controllers/admin/transcript_imports_controller_test.rb test/jobs/admin/transcript_import_workflow_job_test.rb test/services/documents/transcript_downloader_test.rb test/services/documents/uploaded_transcript_importer_test.rb
```

Expected: only transcript SRT upload changes appear.

- [ ] **Step 5: Commit any verification-only cleanup**

If RuboCop or tests required small cleanup changes, commit them:

```bash
git add app test
git commit -m "fix: polish transcript srt upload"
```

If there are no cleanup changes, do not create an empty commit.
