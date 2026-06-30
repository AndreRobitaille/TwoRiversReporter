# Admin Transcript Import Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `/admin/transcript_imports`, a background workflow, and persisted logs for importing YouTube captions, refreshing meeting summaries, and reanalyzing topics.

**Architecture:** Add a `TranscriptImport` record as the durable workflow log, refactor transcript download/store code into a reusable service, and add one admin workflow job that coordinates transcript import, summary generation, and topic reanalysis. The admin controller starts workflows, runs non-destructive URL prechecks, and renders a two-column admin utility page with recent job status.

**Tech Stack:** Rails, Active Job, Active Storage, Minitest integration/job tests, `yt-dlp`, server-rendered ERB with minimal JavaScript.

---

## File Structure

- Create `db/migrate/*_create_transcript_imports.rb` — persisted workflow state and troubleshooting data.
- Create `app/models/transcript_import.rb` — status validations, step logging helpers, and failure/completion helpers.
- Create `app/services/documents/transcript_downloader.rb` — reusable YouTube caption download/store/precheck service with `Dir.mktmpdir` cleanup.
- Modify `app/jobs/documents/download_transcript_job.rb` — delegate to `Documents::TranscriptDownloader` so existing pipeline behavior remains intact.
- Create `app/jobs/admin/transcript_import_workflow_job.rb` — deterministic admin workflow job.
- Create `app/controllers/admin/transcript_imports_controller.rb` — admin page, workflow create action, and URL precheck action.
- Modify `config/routes.rb` — add `resource :transcript_imports` under admin scope with `check_url` collection action.
- Modify `app/views/layouts/admin.html.erb` — add a nav link for Transcript Imports.
- Create `app/views/admin/transcript_imports/show.html.erb` — two-column form/status UI.
- Modify `app/assets/stylesheets/application.css` — focused admin two-column/status styles.
- Create `test/models/transcript_import_test.rb` — model status/log tests.
- Create `test/services/documents/transcript_downloader_test.rb` — downloader/precheck behavior and temp cleanup expectations.
- Modify `test/jobs/documents/download_transcript_job_test.rb` — update expectations to service-backed implementation without changing public behavior.
- Create `test/jobs/admin/transcript_import_workflow_job_test.rb` — workflow status, logging, summary, reanalysis, and failure tests.
- Create `test/controllers/admin/transcript_imports_controller_test.rb` — auth, render, create, validation, enqueue, and precheck tests.

---

### Task 1: Add `TranscriptImport` model and migration

**Files:**
- Create: `db/migrate/*_create_transcript_imports.rb`
- Create: `app/models/transcript_import.rb`
- Test: `test/models/transcript_import_test.rb`

- [ ] **Step 1: Write the failing model test**

Create `test/models/transcript_import_test.rb`:

```ruby
require "test_helper"

class TranscriptImportTest < ActiveSupport::TestCase
  setup do
    @meeting = meetings(:one)
  end

  test "validates status" do
    transcript_import = TranscriptImport.new(
      meeting: @meeting,
      youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o",
      status: "mystery"
    )

    assert_not transcript_import.valid?
    assert_includes transcript_import.errors[:status], "is not included in the list"
  end

  test "appends structured step logs" do
    transcript_import = TranscriptImport.create!(
      meeting: @meeting,
      youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o",
      status: "queued"
    )

    freeze_time do
      transcript_import.append_step_log!(
        step: "download_transcript",
        message: "Downloaded transcript",
        metadata: { meeting_document_id: 123, text_chars: 456 }
      )
    end

    log_entry = transcript_import.reload.step_logs.last
    assert_equal "info", log_entry["level"]
    assert_equal "download_transcript", log_entry["step"]
    assert_equal "Downloaded transcript", log_entry["message"]
    assert_equal 123, log_entry.dig("metadata", "meeting_document_id")
    assert_equal 456, log_entry.dig("metadata", "text_chars")
    assert_equal Time.current.iso8601, log_entry["at"]
  end

  test "mark_failed stores troubleshooting details" do
    transcript_import = TranscriptImport.create!(
      meeting: @meeting,
      youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o",
      status: "running",
      started_at: 1.minute.ago
    )

    error = RuntimeError.new("yt-dlp failed")
    error.set_backtrace(["app/services/documents/transcript_downloader.rb:42:in `download'"])

    freeze_time do
      transcript_import.mark_failed!(error, step: "download_transcript")
    end

    transcript_import.reload
    assert_equal "failed", transcript_import.status
    assert_equal Time.current, transcript_import.finished_at
    assert_equal "RuntimeError", transcript_import.error_class
    assert_equal "yt-dlp failed", transcript_import.error_message
    assert_includes transcript_import.error_backtrace, "transcript_downloader.rb:42"
    assert_equal "error", transcript_import.step_logs.last["level"]
    assert_equal "download_transcript", transcript_import.step_logs.last["step"]
  end

  test "mark_completed records affected topics and document" do
    transcript_import = TranscriptImport.create!(
      meeting: @meeting,
      youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o",
      status: "running",
      started_at: 1.minute.ago
    )

    document = meeting_documents(:one)

    freeze_time do
      transcript_import.mark_completed!(meeting_document: document, affected_topic_ids: [3, 1, 3])
    end

    transcript_import.reload
    assert_equal "completed", transcript_import.status
    assert_equal Time.current, transcript_import.finished_at
    assert_equal document.id, transcript_import.meeting_document_id
    assert_equal [1, 3], transcript_import.affected_topic_ids
  end
end
```

- [ ] **Step 2: Run the model test to verify it fails**

Run:

```bash
bin/rails test test/models/transcript_import_test.rb
```

Expected: FAIL with `NameError: uninitialized constant TranscriptImport`.

- [ ] **Step 3: Create the migration**

Run:

```bash
bin/rails generate migration CreateTranscriptImports meeting:references youtube_url:string status:string started_at:datetime finished_at:datetime meeting_document_id:bigint affected_topic_ids:json step_logs:json error_class:string error_message:text error_backtrace:text
```

Edit the generated migration to this shape:

```ruby
class CreateTranscriptImports < ActiveRecord::Migration[8.0]
  def change
    create_table :transcript_imports do |t|
      t.references :meeting, null: false, foreign_key: true
      t.string :youtube_url, null: false
      t.string :status, null: false, default: "queued"
      t.datetime :started_at
      t.datetime :finished_at
      t.bigint :meeting_document_id
      t.json :affected_topic_ids, null: false, default: []
      t.json :step_logs, null: false, default: []
      t.string :error_class
      t.text :error_message
      t.text :error_backtrace

      t.timestamps
    end

    add_foreign_key :transcript_imports, :meeting_documents, column: :meeting_document_id
    add_index :transcript_imports, :status
    add_index :transcript_imports, :created_at
  end
end
```

- [ ] **Step 4: Create the model**

Create `app/models/transcript_import.rb`:

```ruby
class TranscriptImport < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze

  belongs_to :meeting
  belongs_to :meeting_document, optional: true

  validates :youtube_url, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }

  def append_step_log!(step:, message:, level: "info", metadata: {})
    entry = {
      at: Time.current.iso8601,
      level: level,
      step: step,
      message: message,
      metadata: metadata
    }.deep_stringify_keys

    update!(step_logs: Array(step_logs) + [entry])
  end

  def mark_running!
    update!(status: "running", started_at: Time.current)
  end

  def mark_failed!(error, step:)
    append_step_log!(
      step: step,
      level: "error",
      message: error.message,
      metadata: { error_class: error.class.name }
    )

    update!(
      status: "failed",
      finished_at: Time.current,
      error_class: error.class.name,
      error_message: error.message,
      error_backtrace: Array(error.backtrace).join("\n")
    )
  end

  def mark_completed!(meeting_document:, affected_topic_ids: [])
    update!(
      status: "completed",
      finished_at: Time.current,
      meeting_document: meeting_document,
      affected_topic_ids: Array(affected_topic_ids).map(&:to_i).uniq.sort
    )
  end
end
```

- [ ] **Step 5: Migrate and run the model test**

Run:

```bash
bin/rails db:migrate
bin/rails test test/models/transcript_import_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate app/models/transcript_import.rb test/models/transcript_import_test.rb db/schema.rb
git commit -m "feat: add transcript import workflow records"
```

---

### Task 2: Extract transcript download/precheck service

**Files:**
- Create: `app/services/documents/transcript_downloader.rb`
- Modify: `app/jobs/documents/download_transcript_job.rb`
- Test: `test/services/documents/transcript_downloader_test.rb`
- Test: `test/jobs/documents/download_transcript_job_test.rb`

- [ ] **Step 1: Write the failing service tests**

Create `test/services/documents/transcript_downloader_test.rb`:

```ruby
require "test_helper"

class Documents::TranscriptDownloaderTest < ActiveSupport::TestCase
  setup do
    @meeting = meetings(:one)
    @url = "https://www.youtube.com/watch?v=8_qRxfE6f9o"
  end

  test "download_and_store creates transcript document with attached srt" do
    srt_content = <<~SRT
      1
      00:00:01,000 --> 00:00:02,000
      Hello council.

      2
      00:00:03,000 --> 00:00:04,000
      We are discussing the agenda.
    SRT

    Documents::TranscriptDownloader.any_instance.stub(:download_captions, [srt_content, "Hello council.\n\nWe are discussing the agenda."]) do
      result = Documents::TranscriptDownloader.new(meeting: @meeting, video_url: @url).download_and_store

      assert result.created?
      assert_equal "created", result.status
      assert_equal "transcript", result.meeting_document.document_type
      assert_equal @url, result.meeting_document.source_url
      assert_equal "Hello council.\n\nWe are discussing the agenda.", result.meeting_document.extracted_text
      assert result.meeting_document.file.attached?
    end
  end

  test "download_and_store reuses existing transcript document" do
    existing = @meeting.meeting_documents.create!(
      document_type: "transcript",
      source_url: @url,
      extracted_text: "Existing transcript",
      text_quality: "auto_transcribed",
      text_chars: 19,
      fetched_at: Time.current
    )

    result = Documents::TranscriptDownloader.new(meeting: @meeting, video_url: @url).download_and_store

    assert result.reused?
    assert_equal "reused", result.status
    assert_equal existing, result.meeting_document
  end

  test "download_and_store rejects invalid urls" do
    error = assert_raises(Documents::TranscriptDownloader::InvalidUrlError) do
      Documents::TranscriptDownloader.new(meeting: @meeting, video_url: "https://example.com/video").download_and_store
    end

    assert_equal "Invalid YouTube URL", error.message
  end

  test "precheck returns invalid_url without shelling out" do
    result = Documents::TranscriptDownloader.precheck("https://example.com/video")

    assert_equal :invalid_url, result.status
    assert_equal "URL must be a youtube.com watch URL", result.message
  end

  test "precheck reports captions available" do
    stdout = { "automatic_captions" => { "en" => [{ "ext" => "srv3" }] } }.to_json

    Open3.stub(:capture3, [stdout, "", stub(success?: true)]) do
      result = Documents::TranscriptDownloader.precheck(@url)

      assert_equal :captions_available, result.status
      assert_equal "English captions appear to be available", result.message
    end
  end

  test "precheck reports captions missing" do
    stdout = { "automatic_captions" => {}, "subtitles" => {} }.to_json

    Open3.stub(:capture3, [stdout, "", stub(success?: true)]) do
      result = Documents::TranscriptDownloader.precheck(@url)

      assert_equal :captions_missing, result.status
      assert_equal "No English captions were found", result.message
    end
  end

  test "precheck reports verification unavailable when yt-dlp fails" do
    Open3.stub(:capture3, ["", "Sign in to confirm you're not a bot", stub(success?: false)]) do
      result = Documents::TranscriptDownloader.precheck(@url)

      assert_equal :verification_unavailable, result.status
      assert_includes result.message, "could not verify captions"
      assert_includes result.details, "not a bot"
    end
  end
end
```

- [ ] **Step 2: Run the service test to verify it fails**

Run:

```bash
bin/rails test test/services/documents/transcript_downloader_test.rb
```

Expected: FAIL with `uninitialized constant Documents::TranscriptDownloader`.

- [ ] **Step 3: Implement the downloader service**

Create `app/services/documents/transcript_downloader.rb`:

```ruby
require "open3"
require "json"

module Documents
  class TranscriptDownloader
    YOUTUBE_URL_PATTERN = %r{\Ahttps://www\.youtube\.com/watch\?v=[A-Za-z0-9_-]+\z}

    InvalidUrlError = Class.new(StandardError)
    DownloadError = Class.new(StandardError)

    Result = Struct.new(:status, :meeting_document, keyword_init: true) do
      def created? = status == "created"
      def reused? = status == "reused"
    end

    PrecheckResult = Struct.new(:status, :message, :details, keyword_init: true)

    def self.valid_url?(video_url)
      video_url.to_s.match?(YOUTUBE_URL_PATTERN)
    end

    def self.precheck(video_url)
      unless valid_url?(video_url)
        return PrecheckResult.new(status: :invalid_url, message: "URL must be a youtube.com watch URL", details: nil)
      end

      stdout, stderr, status = Open3.capture3(
        "yt-dlp",
        "--dump-single-json",
        "--skip-download",
        video_url
      )

      unless status.success?
        return PrecheckResult.new(
          status: :verification_unavailable,
          message: "This server could not verify captions, likely because YouTube blocked or rate-limited the request",
          details: stderr.presence || stdout.presence
        )
      end

      metadata = JSON.parse(stdout)
      captions = metadata.fetch("subtitles", {}).fetch("en", [])
      auto_captions = metadata.fetch("automatic_captions", {}).fetch("en", [])

      if captions.any? || auto_captions.any?
        PrecheckResult.new(status: :captions_available, message: "English captions appear to be available", details: nil)
      else
        PrecheckResult.new(status: :captions_missing, message: "No English captions were found", details: nil)
      end
    rescue JSON::ParserError => error
      PrecheckResult.new(
        status: :verification_unavailable,
        message: "This server could not verify captions because yt-dlp returned unreadable metadata",
        details: error.message
      )
    end

    def initialize(meeting:, video_url:)
      @meeting = meeting
      @video_url = video_url
    end

    def download_and_store
      raise InvalidUrlError, "Invalid YouTube URL" unless self.class.valid_url?(@video_url)

      existing = @meeting.meeting_documents.find_by(document_type: "transcript")
      return Result.new(status: "reused", meeting_document: existing) if existing

      srt_content, plain_text = download_captions
      raise DownloadError, "yt-dlp produced no transcript text" if plain_text.blank?

      document = @meeting.meeting_documents.create!(
        document_type: "transcript",
        source_url: @video_url,
        extracted_text: plain_text,
        text_quality: "auto_transcribed",
        text_chars: plain_text.length,
        fetched_at: Time.current
      )

      document.file.attach(
        io: StringIO.new(srt_content),
        filename: "transcript-#{@meeting.starts_at.to_date}.srt",
        content_type: "text/srt"
      )

      Result.new(status: "created", meeting_document: document)
    end

    private

    def download_captions
      Dir.mktmpdir("transcript") do |tmpdir|
        stdout, stderr, status = Open3.capture3(
          "yt-dlp",
          "--write-auto-sub",
          "--sub-lang", "en",
          "--sub-format", "srt",
          "--skip-download",
          "-o", "#{tmpdir}/video",
          @video_url
        )

        raise DownloadError, "yt-dlp failed: #{stderr.strip.presence || stdout.strip}" unless status.success?

        srt_file = Dir.glob("#{tmpdir}/*.srt").first
        raise DownloadError, "yt-dlp produced no SRT file" unless srt_file

        srt_content = File.read(srt_file)
        [srt_content, parse_srt(srt_content)]
      end
    end

    def parse_srt(srt_content)
      srt_content
        .gsub(/^\d+\s*$/, "")
        .gsub(/^\d{2}:\d{2}:\d{2},\d{3}\s*-->.*$/, "")
        .gsub(/\n{3,}/, "\n\n")
        .strip
    end
  end
end
```

- [ ] **Step 4: Update `Documents::DownloadTranscriptJob` to use the service**

Replace `app/jobs/documents/download_transcript_job.rb` with:

```ruby
module Documents
  class DownloadTranscriptJob < ApplicationJob
    queue_as :default

    def perform(meeting_id, video_url)
      meeting = Meeting.find(meeting_id)
      result = Documents::TranscriptDownloader.new(meeting: meeting, video_url: video_url).download_and_store

      unless meeting.meeting_summaries.exists?(summary_type: "minutes_recap")
        SummarizeMeetingJob.perform_later(meeting.id)
      end

      Rails.logger.info(
        "DownloadTranscriptJob: #{result.status} transcript for meeting_id=#{meeting.id} " \
        "meeting_document_id=#{result.meeting_document.id}"
      )
    rescue Documents::TranscriptDownloader::InvalidUrlError => error
      Rails.logger.error "DownloadTranscriptJob: #{error.message}: #{video_url}"
    rescue Documents::TranscriptDownloader::DownloadError => error
      Rails.logger.error "DownloadTranscriptJob: #{error.message} for #{video_url}"
    end
  end
end
```

- [ ] **Step 5: Run service and existing transcript job tests**

Run:

```bash
bin/rails test test/services/documents/transcript_downloader_test.rb test/jobs/documents/download_transcript_job_test.rb
```

Expected: PASS. If `test/jobs/documents/download_transcript_job_test.rb` asserts private methods from the old job, move those assertions to `test/services/documents/transcript_downloader_test.rb` and keep job tests focused on public behavior: invalid URL logs, document creation, existing transcript reuse, and summary enqueue.

- [ ] **Step 6: Commit**

```bash
git add app/services/documents/transcript_downloader.rb app/jobs/documents/download_transcript_job.rb test/services/documents/transcript_downloader_test.rb test/jobs/documents/download_transcript_job_test.rb
git commit -m "refactor: extract transcript downloader service"
```

---

### Task 3: Add admin transcript import workflow job

**Files:**
- Create: `app/jobs/admin/transcript_import_workflow_job.rb`
- Test: `test/jobs/admin/transcript_import_workflow_job_test.rb`

- [ ] **Step 1: Write the failing workflow job tests**

Create `test/jobs/admin/transcript_import_workflow_job_test.rb`:

```ruby
require "test_helper"

class Admin::TranscriptImportWorkflowJobTest < ActiveJob::TestCase
  setup do
    @meeting = meetings(:one)
    @transcript_import = TranscriptImport.create!(
      meeting: @meeting,
      youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o",
      status: "queued"
    )
  end

  test "successful workflow downloads transcript summarizes meeting and reanalyzes topics" do
    document = @meeting.meeting_documents.create!(
      document_type: "transcript",
      source_url: @transcript_import.youtube_url,
      extracted_text: "Transcript text",
      text_quality: "auto_transcribed",
      text_chars: 15,
      fetched_at: Time.current
    )
    download_result = Documents::TranscriptDownloader::Result.new(status: "created", meeting_document: document)
    reanalysis_result = Topics::MeetingReanalysisService::Result.new(
      meeting: @meeting,
      before_topic_ids: [1],
      after_topic_ids: [2],
      affected_topic_ids: [1, 2],
      selector_ids: [],
      wire_ids: []
    )

    downloader = Minitest::Mock.new
    downloader.expect(:download_and_store, download_result)

    reanalysis = Minitest::Mock.new
    reanalysis.expect(:call, reanalysis_result)

    Documents::TranscriptDownloader.stub(:new, downloader) do
      Topics::MeetingReanalysisService.stub(:new, reanalysis) do
        SummarizeMeetingJob.stub(:perform_now, true) do
          Admin::TranscriptImportWorkflowJob.perform_now(@transcript_import.id)
        end
      end
    end

    downloader.verify
    reanalysis.verify

    @transcript_import.reload
    assert_equal "completed", @transcript_import.status
    assert_equal document.id, @transcript_import.meeting_document_id
    assert_equal [1, 2], @transcript_import.affected_topic_ids
    assert @transcript_import.step_logs.any? { |entry| entry["step"] == "download_transcript" }
    assert @transcript_import.step_logs.any? { |entry| entry["step"] == "summarize_meeting" }
    assert @transcript_import.step_logs.any? { |entry| entry["step"] == "reanalyze_topics" }
  end

  test "workflow records reused transcript" do
    document = @meeting.meeting_documents.create!(
      document_type: "transcript",
      source_url: @transcript_import.youtube_url,
      extracted_text: "Existing transcript",
      text_quality: "auto_transcribed",
      text_chars: 19,
      fetched_at: Time.current
    )
    download_result = Documents::TranscriptDownloader::Result.new(status: "reused", meeting_document: document)
    reanalysis_result = Topics::MeetingReanalysisService::Result.new(
      meeting: @meeting,
      before_topic_ids: [],
      after_topic_ids: [],
      affected_topic_ids: [],
      selector_ids: [],
      wire_ids: []
    )

    downloader = Minitest::Mock.new
    downloader.expect(:download_and_store, download_result)
    reanalysis = Minitest::Mock.new
    reanalysis.expect(:call, reanalysis_result)

    Documents::TranscriptDownloader.stub(:new, downloader) do
      Topics::MeetingReanalysisService.stub(:new, reanalysis) do
        SummarizeMeetingJob.stub(:perform_now, true) do
          Admin::TranscriptImportWorkflowJob.perform_now(@transcript_import.id)
        end
      end
    end

    assert_equal "completed", @transcript_import.reload.status
    assert @transcript_import.step_logs.any? { |entry| entry["message"].include?("Reused existing transcript") }
  end

  test "workflow stores failure details" do
    error = Documents::TranscriptDownloader::DownloadError.new("yt-dlp failed: blocked")
    downloader = Minitest::Mock.new
    downloader.expect(:download_and_store, nil) { raise error }

    Documents::TranscriptDownloader.stub(:new, downloader) do
      Admin::TranscriptImportWorkflowJob.perform_now(@transcript_import.id)
    end

    @transcript_import.reload
    assert_equal "failed", @transcript_import.status
    assert_equal "Documents::TranscriptDownloader::DownloadError", @transcript_import.error_class
    assert_equal "yt-dlp failed: blocked", @transcript_import.error_message
    assert @transcript_import.step_logs.any? { |entry| entry["level"] == "error" }
  end
end
```

- [ ] **Step 2: Run the workflow job test to verify it fails**

Run:

```bash
bin/rails test test/jobs/admin/transcript_import_workflow_job_test.rb
```

Expected: FAIL with `uninitialized constant Admin::TranscriptImportWorkflowJob`.

- [ ] **Step 3: Implement the workflow job**

Create `app/jobs/admin/transcript_import_workflow_job.rb`:

```ruby
module Admin
  class TranscriptImportWorkflowJob < ApplicationJob
    queue_as :default

    def perform(transcript_import_id)
      transcript_import = TranscriptImport.find(transcript_import_id)
      transcript_import.mark_running!

      log(transcript_import, "start", "Starting transcript import workflow")

      download_result = download_transcript(transcript_import)
      summarize_meeting(transcript_import)
      reanalysis_result = reanalyze_topics(transcript_import)

      transcript_import.mark_completed!(
        meeting_document: download_result.meeting_document,
        affected_topic_ids: reanalysis_result.affected_topic_ids
      )
      log(
        transcript_import,
        "complete",
        "Completed transcript import workflow",
        meeting_document_id: download_result.meeting_document.id,
        affected_topic_ids: reanalysis_result.affected_topic_ids
      )
    rescue StandardError => error
      handle_failure(transcript_import, error)
    end

    private

    def download_transcript(transcript_import)
      result = Documents::TranscriptDownloader.new(
        meeting: transcript_import.meeting,
        video_url: transcript_import.youtube_url
      ).download_and_store

      message = result.reused? ? "Reused existing transcript document" : "Downloaded transcript document"
      log(
        transcript_import,
        "download_transcript",
        message,
        status: result.status,
        meeting_document_id: result.meeting_document.id,
        text_chars: result.meeting_document.text_chars
      )

      result
    end

    def summarize_meeting(transcript_import)
      log(transcript_import, "summarize_meeting", "Starting meeting summary refresh")
      SummarizeMeetingJob.perform_now(transcript_import.meeting_id)
      log(transcript_import, "summarize_meeting", "Finished meeting summary refresh")
    end

    def reanalyze_topics(transcript_import)
      log(transcript_import, "reanalyze_topics", "Starting topic reanalysis")
      result = Topics::MeetingReanalysisService.new(transcript_import.meeting_id).call
      log(
        transcript_import,
        "reanalyze_topics",
        "Finished topic reanalysis",
        before_topic_ids: result.before_topic_ids,
        after_topic_ids: result.after_topic_ids,
        affected_topic_ids: result.affected_topic_ids
      )
      result
    end

    def handle_failure(transcript_import, error)
      Rails.logger.error(
        "Admin::TranscriptImportWorkflowJob failed " \
        "transcript_import_id=#{transcript_import&.id} " \
        "meeting_id=#{transcript_import&.meeting_id} " \
        "youtube_url=#{transcript_import&.youtube_url} " \
        "error_class=#{error.class.name} error_message=#{error.message}"
      )

      if transcript_import&.persisted?
        transcript_import.mark_failed!(error, step: "workflow")
      else
        raise error
      end
    end

    def log(transcript_import, step, message, metadata = {})
      Rails.logger.info(
        "TranscriptImport #{step}: #{message} " \
        "transcript_import_id=#{transcript_import.id} " \
        "meeting_id=#{transcript_import.meeting_id} " \
        "youtube_url=#{transcript_import.youtube_url} " \
        "metadata=#{metadata.inspect}"
      )
      transcript_import.append_step_log!(step: step, message: message, metadata: metadata)
    end
  end
end
```

- [ ] **Step 4: Run workflow job test**

Run:

```bash
bin/rails test test/jobs/admin/transcript_import_workflow_job_test.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/admin/transcript_import_workflow_job.rb test/jobs/admin/transcript_import_workflow_job_test.rb
git commit -m "feat: add transcript import workflow job"
```

---

### Task 4: Add admin routes, controller, and page

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/views/layouts/admin.html.erb`
- Create: `app/controllers/admin/transcript_imports_controller.rb`
- Create: `app/views/admin/transcript_imports/show.html.erb`
- Test: `test/controllers/admin/transcript_imports_controller_test.rb`

- [ ] **Step 1: Write the failing controller tests**

Create `test/controllers/admin/transcript_imports_controller_test.rb`:

```ruby
require "test_helper"

class Admin::TranscriptImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @meeting = meetings(:one)
    sign_in_as_admin
  end

  test "shows transcript import page" do
    get admin_transcript_imports_path

    assert_response :success
    assert_select "h1", "Transcript Imports"
    assert_select "form[action='#{admin_transcript_imports_path}']"
    assert_select "select[name='transcript_import[meeting_id]']"
    assert_select "input[name='transcript_import[youtube_url]']"
    assert_select "button", "Begin Import"
    assert_select "aside", /What this job does/
  end

  test "creates transcript import and enqueues workflow job" do
    assert_enqueued_with(job: Admin::TranscriptImportWorkflowJob) do
      post admin_transcript_imports_path, params: {
        transcript_import: {
          meeting_id: @meeting.id,
          youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o"
        }
      }
    end

    transcript_import = TranscriptImport.order(:created_at).last
    assert_equal @meeting, transcript_import.meeting
    assert_equal "queued", transcript_import.status
    assert_redirected_to admin_transcript_imports_path
    assert_equal "Transcript import workflow queued.", flash[:notice]
  end

  test "rejects invalid meeting" do
    assert_no_enqueued_jobs do
      post admin_transcript_imports_path, params: {
        transcript_import: {
          meeting_id: 999_999,
          youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o"
        }
      }
    end

    assert_redirected_to admin_transcript_imports_path
    assert_equal "Choose a valid meeting.", flash[:alert]
  end

  test "rejects invalid youtube url" do
    assert_no_enqueued_jobs do
      post admin_transcript_imports_path, params: {
        transcript_import: {
          meeting_id: @meeting.id,
          youtube_url: "https://example.com/video"
        }
      }
    end

    assert_redirected_to admin_transcript_imports_path
    assert_equal "Enter a valid YouTube watch URL.", flash[:alert]
  end

  test "checks url without creating workflow" do
    result = Documents::TranscriptDownloader::PrecheckResult.new(
      status: :captions_available,
      message: "English captions appear to be available",
      details: nil
    )

    Documents::TranscriptDownloader.stub(:precheck, result) do
      assert_no_difference "TranscriptImport.count" do
        post check_url_admin_transcript_imports_path, params: { youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o" }
      end
    end

    assert_redirected_to admin_transcript_imports_path(youtube_url: "https://www.youtube.com/watch?v=8_qRxfE6f9o")
    assert_equal "English captions appear to be available", flash[:notice]
  end

  private

  def sign_in_as_admin
    post session_url, params: { email_address: @admin.email_address, password: "password" }
    follow_redirect!
    post mfa_session_url, params: { code: ROTP::TOTP.new(@admin.totp_secret).now }
  end
end
```

- [ ] **Step 2: Run the controller test to verify it fails**

Run:

```bash
bin/rails test test/controllers/admin/transcript_imports_controller_test.rb
```

Expected: FAIL with missing route/controller errors.

- [ ] **Step 3: Add routes**

Modify `config/routes.rb` inside the existing `scope :admin` block:

```ruby
resource :transcript_imports, only: %i[show create], controller: "transcript_imports" do
  post :check_url
end
```

- [ ] **Step 4: Add the controller**

Create `app/controllers/admin/transcript_imports_controller.rb`:

```ruby
module Admin
  class TranscriptImportsController < BaseController
    def show
      @meetings = Meeting.includes(:committee).order(starts_at: :desc).limit(250)
      @transcript_imports = TranscriptImport.includes(:meeting, :meeting_document).recent_first.limit(25)
      @selected_meeting_id = params[:meeting_id]
      @youtube_url = params[:youtube_url]
    end

    def create
      meeting = Meeting.find_by(id: transcript_import_params[:meeting_id])
      return redirect_to admin_transcript_imports_path, alert: "Choose a valid meeting." unless meeting

      youtube_url = transcript_import_params[:youtube_url].to_s.strip
      unless Documents::TranscriptDownloader.valid_url?(youtube_url)
        return redirect_to admin_transcript_imports_path(meeting_id: meeting.id, youtube_url: youtube_url), alert: "Enter a valid YouTube watch URL."
      end

      transcript_import = TranscriptImport.create!(
        meeting: meeting,
        youtube_url: youtube_url,
        status: "queued"
      )

      Admin::TranscriptImportWorkflowJob.perform_later(transcript_import.id)

      redirect_to admin_transcript_imports_path, notice: "Transcript import workflow queued."
    end

    helper_method :meeting_option_label, :meeting_filter_text

    def check_url
      youtube_url = submitted_youtube_url
      result = Documents::TranscriptDownloader.precheck(youtube_url)
      flash_key = result.status == :captions_available ? :notice : :alert

      redirect_to admin_transcript_imports_path(youtube_url: youtube_url), flash: { flash_key => result.message }
    end

    private

    def transcript_import_params
      params.require(:transcript_import).permit(:meeting_id, :youtube_url)
    end

    def submitted_youtube_url
      params.dig(:transcript_import, :youtube_url).presence || params[:youtube_url].to_s.strip
    end

    def meeting_option_label(meeting)
      date = meeting.starts_at&.strftime("%b %-d, %Y") || "No date"
      body = meeting.committee&.name || "Meeting"
      "#{body} — #{date} — Meeting ##{meeting.id}"
    end

    def meeting_filter_text(meeting)
      [meeting.id, meeting.title, meeting.committee&.name, meeting.starts_at&.to_date].compact.join(" ")
    end
  end
end
```

- [ ] **Step 5: Add the admin nav link**

In `app/views/layouts/admin.html.erb`, add this near other admin nav links:

```erb
<%= link_to "Transcript Imports", admin_transcript_imports_path %>
```

- [ ] **Step 6: Add the admin view**

Create `app/views/admin/transcript_imports/show.html.erb`:

```erb
<% content_for :title, "Transcript Imports" %>

<section class="admin-section">
  <header class="admin-section__header">
    <div>
      <p class="eyebrow">Admin</p>
      <h1>Transcript Imports</h1>
      <p class="section-lede">Import YouTube captions for a meeting, generate or refresh its summary, and reanalyze related topics in one background workflow.</p>
    </div>
  </header>

  <% if flash[:notice] || flash[:alert] %>
    <div class="flash <%= flash[:alert] ? 'flash--danger' : 'flash--success' %>" role="status">
      <%= flash[:alert] || flash[:notice] %>
    </div>
  <% end %>

  <div class="admin-two-column">
    <main>
      <div class="admin-card">
        <%= form_with url: admin_transcript_imports_path, scope: :transcript_import, local: true do |form| %>
          <div class="field">
            <%= form.label :meeting_id, "Find a meeting" %>
            <input type="search" class="input" data-meeting-filter placeholder="Filter by title, body, date, or meeting ID…">
            <%= form.select :meeting_id,
              @meetings.map { |meeting| [meeting_option_label(meeting), meeting.id, { data: { filter_text: meeting_filter_text(meeting) } }] },
              { selected: @selected_meeting_id, prompt: "Choose a meeting" },
              { class: "input", data: { meeting_select: true } } %>
          </div>

          <div class="field">
            <%= form.label :youtube_url, "YouTube URL" %>
            <div class="inline-controls">
              <%= form.url_field :youtube_url, value: @youtube_url, class: "input", placeholder: "https://www.youtube.com/watch?v=..." %>
              <%= button_tag "Check URL", type: "submit", formaction: check_url_admin_transcript_imports_path, formmethod: :post, name: nil, class: "button button--secondary" %>
            </div>
          </div>

          <%= form.submit "Begin Import", class: "button button--primary" %>
        <% end %>
      </div>

      <section class="admin-card">
        <h2>Recent transcript workflows</h2>
        <% if @transcript_imports.any? %>
          <table class="admin-table">
            <thead>
              <tr>
                <th>Meeting</th>
                <th>Status</th>
                <th>Started</th>
                <th>Last log</th>
              </tr>
            </thead>
            <tbody>
              <% @transcript_imports.each do |transcript_import| %>
                <% last_log = Array(transcript_import.step_logs).last %>
                <tr>
                  <td><%= link_to "##{transcript_import.meeting_id} #{transcript_import.meeting.title}", admin_meeting_path(transcript_import.meeting) %></td>
                  <td><span class="status-pill status-pill--<%= transcript_import.status %>"><%= transcript_import.status.titleize %></span></td>
                  <td><%= transcript_import.started_at ? time_ago_in_words(transcript_import.started_at) + " ago" : "Queued" %></td>
                  <td><%= last_log ? last_log["message"] : "Waiting to start" %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% else %>
          <p class="section-empty">No transcript imports have been queued yet.</p>
        <% end %>
      </section>
    </main>

    <aside class="admin-card admin-sidebar">
      <h2>What this job does</h2>
      <ol>
        <li>Checks the meeting and YouTube URL.</li>
        <li>Downloads available English captions.</li>
        <li>Saves the transcript document.</li>
        <li>Generates or refreshes the meeting summary.</li>
        <li>Reanalyzes related topics and briefings.</li>
      </ol>
      <p>The workflow logs each major step and captures failure details so failed imports can be diagnosed from this page.</p>
    </aside>
  </div>
</section>

<script>
  document.addEventListener("DOMContentLoaded", () => {
    const filter = document.querySelector("[data-meeting-filter]");
    const select = document.querySelector("[data-meeting-select]");
    if (!filter || !select) return;

    const options = Array.from(select.options).map((option) => ({
      option,
      text: (option.dataset.filterText || option.textContent || "").toLowerCase()
    }));

    filter.addEventListener("input", () => {
      const query = filter.value.toLowerCase().trim();
      options.forEach(({ option, text }) => {
        option.hidden = query.length > 0 && !text.includes(query);
      });
    });
  });
</script>
```

- [ ] **Step 7: Run controller tests**

Run:

```bash
bin/rails test test/controllers/admin/transcript_imports_controller_test.rb
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/admin/transcript_imports_controller.rb app/views/admin/transcript_imports/show.html.erb app/views/layouts/admin.html.erb test/controllers/admin/transcript_imports_controller_test.rb
git commit -m "feat: add admin transcript import page"
```

---

### Task 5: Add focused styling for the admin two-column page

**Files:**
- Modify: `app/assets/stylesheets/application.css`
- Test: `test/controllers/admin/transcript_imports_controller_test.rb`

- [ ] **Step 1: Add minimal page styles**

Add these styles to `app/assets/stylesheets/application.css`:

```css
.admin-two-column {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 20rem;
  gap: 1.5rem;
  align-items: start;
}

.admin-sidebar {
  position: sticky;
  top: 1rem;
}

.inline-controls {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 0.75rem;
  align-items: end;
}

.status-pill {
  display: inline-flex;
  align-items: center;
  border-radius: 999px;
  padding: 0.2rem 0.55rem;
  font-size: 0.85rem;
  font-weight: 700;
  background: #e2e8f0;
  color: #334155;
}

.status-pill--queued,
.status-pill--running {
  background: #e0f2fe;
  color: #075985;
}

.status-pill--completed {
  background: #dcfce7;
  color: #166534;
}

.status-pill--failed {
  background: #fee2e2;
  color: #991b1b;
}

@media (max-width: 900px) {
  .admin-two-column {
    grid-template-columns: 1fr;
  }

  .admin-sidebar {
    position: static;
  }

  .inline-controls {
    grid-template-columns: 1fr;
  }
}
```

- [ ] **Step 2: Run the controller page test**

Run:

```bash
bin/rails test test/controllers/admin/transcript_imports_controller_test.rb
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets test/controllers/admin/transcript_imports_controller_test.rb
git commit -m "style: polish admin transcript import page"
```

---

### Task 6: Full verification and cleanup

**Files:**
- Modify only files needed to fix test/lint failures discovered by verification.

- [ ] **Step 1: Run focused tests**

Run:

```bash
bin/rails test test/models/transcript_import_test.rb test/services/documents/transcript_downloader_test.rb test/jobs/documents/download_transcript_job_test.rb test/jobs/admin/transcript_import_workflow_job_test.rb test/controllers/admin/transcript_imports_controller_test.rb
```

Expected: PASS.

- [ ] **Step 2: Run broader relevant tests**

Run:

```bash
bin/rails test test/jobs/scrapers/discover_transcripts_job_test.rb test/jobs/summarize_meeting_job_test.rb test/controllers/admin/meetings_controller_test.rb test/controllers/admin/generated_images_controller_test.rb
```

Expected: PASS.

- [ ] **Step 3: Run lint**

Run:

```bash
bin/rubocop
```

Expected: PASS.

- [ ] **Step 4: Check git diff for accidental files**

Run:

```bash
git status --short
git diff --stat
```

Expected: only intended application/test/schema files are changed. `.superpowers/` mockup files should remain untracked and must not be committed.

- [ ] **Step 5: Commit verification fixes if needed**

If Step 1–3 required fixes, commit them:

```bash
git add app test config db
git commit -m "fix: stabilize admin transcript import workflow"
```

If no fixes were required, do not create an empty commit.
