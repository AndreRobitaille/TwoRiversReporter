# YouTube Transcript Ingestion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ingest YouTube auto-generated captions from council meeting recordings to produce same-day preliminary summaries, then enrich minutes-based summaries with transcript context when minutes arrive.

**Architecture:** Two new jobs (`DiscoverTranscriptsJob`, `DownloadTranscriptJob`) form a standalone pipeline triggered by the existing `DiscoverMeetingsJob`. Transcripts are stored as `MeetingDocument` records with `document_type: "transcript"`. `SummarizeMeetingJob` gains transcript awareness: uses transcript as primary source when no minutes exist, and as supplementary context when minutes arrive later.

**Tech Stack:** Rails 8.1, yt-dlp (system binary), Open3, Solid Queue, Minitest

**Spec:** `docs/superpowers/specs/2026-04-09-youtube-transcript-ingestion-design.md`

---

### Task 0: Create feature branch

- [ ] **Step 1: Create and switch to feature branch**

```bash
git checkout -b feature/youtube-transcript-ingestion
```

---

### Task 1: Add yt-dlp to Dockerfile

**Files:**
- Modify: `Dockerfile:17-21`

- [ ] **Step 1: Add yt-dlp installation to the base stage**

In `Dockerfile`, after the `apt-get install` line and before the `rm -rf` cleanup, add yt-dlp download:

```dockerfile
# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client poppler-utils tesseract-ocr && \
    curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp && \
    chmod +x /usr/local/bin/yt-dlp && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
```

- [ ] **Step 2: Verify the Dockerfile builds**

Run: `docker build --target base -t trr-base-test . 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Dockerfile
git commit -m "build: add yt-dlp to Docker image for YouTube transcript support"
```

---

### Task 2: Update Meeting#document_status

**Files:**
- Modify: `app/models/meeting.rb:17-30`
- Test: `test/models/meeting_test.rb` (add new test)

- [ ] **Step 1: Write the failing test**

Add to `test/models/meeting_test.rb`:

```ruby
test "document_status returns :transcript when transcript exists but no minutes or packet" do
  meeting = Meeting.create!(
    body_name: "City Council",
    detail_page_url: "http://example.com/meeting-transcript-test",
    starts_at: 1.day.ago
  )
  meeting.meeting_documents.create!(
    document_type: "transcript",
    source_url: "https://www.youtube.com/watch?v=test123"
  )
  assert_equal :transcript, meeting.document_status
end

test "document_status returns :minutes even when transcript exists" do
  meeting = Meeting.create!(
    body_name: "City Council",
    detail_page_url: "http://example.com/meeting-transcript-test-2",
    starts_at: 1.day.ago
  )
  meeting.meeting_documents.create!(
    document_type: "minutes_pdf",
    source_url: "http://example.com/minutes.pdf"
  )
  meeting.meeting_documents.create!(
    document_type: "transcript",
    source_url: "https://www.youtube.com/watch?v=test123"
  )
  assert_equal :minutes, meeting.document_status
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/meeting_test.rb -n "/document_status.*transcript/"`
Expected: First test FAILS (`:transcript` not returned), second may pass trivially

- [ ] **Step 3: Update document_status method**

In `app/models/meeting.rb`, replace the `document_status` method:

```ruby
def document_status
  docs = association(:meeting_documents).loaded? ? meeting_documents : meeting_documents.load

  if docs.any? { |d| d.document_type == "minutes_pdf" }
    :minutes
  elsif docs.any? { |d| d.document_type == "packet_pdf" }
    :packet
  elsif docs.any? { |d| d.document_type == "transcript" }
    :transcript
  elsif docs.any? { |d| d.document_type == "agenda_pdf" }
    :agenda
  else
    :none
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/meeting_test.rb -n "/document_status.*transcript/"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/meeting.rb test/models/meeting_test.rb
git commit -m "feat: add transcript tier to Meeting#document_status"
```

---

### Task 3: Create DiscoverTranscriptsJob

**Files:**
- Create: `app/jobs/scrapers/discover_transcripts_job.rb`
- Create: `test/jobs/scrapers/discover_transcripts_job_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/jobs/scrapers/discover_transcripts_job_test.rb`:

```ruby
require "test_helper"

module Scrapers
  class DiscoverTranscriptsJobTest < ActiveJob::TestCase
    setup do
      @council_meeting = Meeting.create!(
        body_name: "City Council Meeting",
        detail_page_url: "http://example.com/council-apr-6",
        starts_at: 1.day.ago
      )
      @work_session = Meeting.create!(
        body_name: "City Council Work Session",
        detail_page_url: "http://example.com/ws-mar-30",
        starts_at: 2.days.ago
      )
      # Non-council meeting should be ignored
      @plan_commission = Meeting.create!(
        body_name: "Plan Commission",
        detail_page_url: "http://example.com/plan-commission",
        starts_at: 1.day.ago
      )
      # Old meeting outside 48-hour window should be ignored
      @old_meeting = Meeting.create!(
        body_name: "City Council Meeting",
        detail_page_url: "http://example.com/council-old",
        starts_at: 5.days.ago
      )
    end

    test "parses standard council meeting title and enqueues download" do
      yt_output = "S8rW22zizHc | Two Rivers City Council Meeting for Monday, #{@council_meeting.starts_at.strftime('%B %-d, %Y')}\n"

      Open3.stub :capture3, [yt_output, "", stub_status(true)] do
        assert_enqueued_with(job: Documents::DownloadTranscriptJob) do
          DiscoverTranscriptsJob.perform_now
        end
      end
    end

    test "parses work session title and enqueues download" do
      yt_output = "pWhrHg4X0tU | Two Rivers City Council Work Session for Monday, #{@work_session.starts_at.strftime('%B %-d, %Y')}\n"

      Open3.stub :capture3, [yt_output, "", stub_status(true)] do
        assert_enqueued_with(job: Documents::DownloadTranscriptJob) do
          DiscoverTranscriptsJob.perform_now
        end
      end
    end

    test "skips videos that cannot be parsed" do
      yt_output = "abc123 | Some Random Video Title\n"

      Open3.stub :capture3, [yt_output, "", stub_status(true)] do
        assert_no_enqueued_jobs(only: Documents::DownloadTranscriptJob) do
          DiscoverTranscriptsJob.perform_now
        end
      end
    end

    test "skips meetings that already have a transcript" do
      @council_meeting.meeting_documents.create!(
        document_type: "transcript",
        source_url: "https://www.youtube.com/watch?v=S8rW22zizHc"
      )
      yt_output = "S8rW22zizHc | Two Rivers City Council Meeting for Monday, #{@council_meeting.starts_at.strftime('%B %-d, %Y')}\n"

      Open3.stub :capture3, [yt_output, "", stub_status(true)] do
        assert_no_enqueued_jobs(only: Documents::DownloadTranscriptJob) do
          DiscoverTranscriptsJob.perform_now
        end
      end
    end

    test "skips non-council meetings" do
      yt_output = "abc123 | Plan Commission for Monday, #{@plan_commission.starts_at.strftime('%B %-d, %Y')}\n"

      Open3.stub :capture3, [yt_output, "", stub_status(true)] do
        assert_no_enqueued_jobs(only: Documents::DownloadTranscriptJob) do
          DiscoverTranscriptsJob.perform_now
        end
      end
    end

    test "handles yt-dlp failure gracefully" do
      Open3.stub :capture3, ["", "ERROR: network error", stub_status(false)] do
        assert_nothing_raised do
          DiscoverTranscriptsJob.perform_now
        end
      end
    end

    private

    def stub_status(success)
      status = Minitest::Mock.new
      status.expect :success?, success
      status
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/scrapers/discover_transcripts_job_test.rb`
Expected: FAIL (class not found)

- [ ] **Step 3: Implement DiscoverTranscriptsJob**

Create `app/jobs/scrapers/discover_transcripts_job.rb`:

```ruby
require "open3"

module Scrapers
  class DiscoverTranscriptsJob < ApplicationJob
    queue_as :default

    YOUTUBE_CHANNEL_URL = "https://www.youtube.com/@Two_Rivers_WI/streams"

    # Matches: "Two Rivers City Council Meeting for Monday, April 6, 2026"
    # Matches: "Two Rivers City Council Work Session for Monday, March 30, 2026"
    TITLE_PATTERN = /(?:City Council (?:Meeting|Work Session)) for \w+, (.+)$/i

    ELIGIBLE_BODY_KEYWORDS = ["council", "work session"].freeze

    def perform
      candidates = find_candidate_meetings
      return if candidates.empty?

      videos = fetch_video_list
      return if videos.empty?

      videos.each do |video_id, title|
        match_and_enqueue(video_id, title, candidates)
      end
    end

    private

    def find_candidate_meetings
      Meeting
        .where("starts_at >= ? AND starts_at <= ?", 48.hours.ago, Time.current)
        .where("body_name ILIKE ? OR body_name ILIKE ?", "%council%", "%work session%")
        .left_joins(:meeting_documents)
        .where.not(meeting_documents: { document_type: "transcript" })
        .or(
          Meeting
            .where("starts_at >= ? AND starts_at <= ?", 48.hours.ago, Time.current)
            .where("body_name ILIKE ? OR body_name ILIKE ?", "%council%", "%work session%")
            .left_joins(:meeting_documents)
            .where(meeting_documents: { id: nil })
        )
        .distinct
    end

    def fetch_video_list
      stdout, stderr, status = Open3.capture3(
        "yt-dlp", "--flat-playlist",
        "--print", "%(id)s | %(title)s",
        YOUTUBE_CHANNEL_URL
      )

      unless status.success?
        Rails.logger.error("DiscoverTranscriptsJob: yt-dlp failed: #{stderr}")
        return []
      end

      stdout.each_line.filter_map do |line|
        parts = line.strip.split(" | ", 2)
        next unless parts.size == 2
        [parts[0], parts[1]]
      end
    end

    def match_and_enqueue(video_id, title, candidates)
      match = title.match(TITLE_PATTERN)
      unless match
        Rails.logger.debug("DiscoverTranscriptsJob: Skipping unparseable title: #{title}")
        return
      end

      date_str = match[1]
      parsed_date = Date.parse(date_str) rescue nil
      unless parsed_date
        Rails.logger.warn("DiscoverTranscriptsJob: Could not parse date '#{date_str}' from title: #{title}")
        return
      end

      meeting = candidates.find { |m| m.starts_at.to_date == parsed_date }
      unless meeting
        Rails.logger.debug("DiscoverTranscriptsJob: No candidate meeting for date #{parsed_date} (title: #{title})")
        return
      end

      video_url = "https://www.youtube.com/watch?v=#{video_id}"
      Rails.logger.info("DiscoverTranscriptsJob: Matched '#{title}' to Meeting ##{meeting.id}, enqueuing download")
      Documents::DownloadTranscriptJob.perform_later(meeting.id, video_url)
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/scrapers/discover_transcripts_job_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/jobs/scrapers/discover_transcripts_job.rb test/jobs/scrapers/discover_transcripts_job_test.rb
git commit -m "feat: add DiscoverTranscriptsJob to find YouTube recordings for recent council meetings"
```

---

### Task 4: Create DownloadTranscriptJob

**Files:**
- Create: `app/jobs/documents/download_transcript_job.rb`
- Create: `test/jobs/documents/download_transcript_job_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/jobs/documents/download_transcript_job_test.rb`:

```ruby
require "test_helper"

module Documents
  class DownloadTranscriptJobTest < ActiveJob::TestCase
    setup do
      @meeting = Meeting.create!(
        body_name: "City Council Meeting",
        detail_page_url: "http://example.com/council-test",
        starts_at: 1.day.ago
      )
      @video_url = "https://www.youtube.com/watch?v=S8rW22zizHc"
    end

    test "downloads transcript and creates MeetingDocument" do
      srt_content = <<~SRT
        1
        00:01:27,560 --> 00:01:30,440
        Testing, testing.

        2
        00:18:12,520 --> 00:18:15,880
        Good evening. Welcome to the city council meeting.
      SRT

      stub_yt_dlp(srt_content) do
        DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
      end

      doc = @meeting.meeting_documents.find_by(document_type: "transcript")
      assert doc, "Should create a transcript document"
      assert_equal @video_url, doc.source_url
      assert_equal "auto_transcribed", doc.text_quality
      assert_includes doc.extracted_text, "Testing, testing."
      assert_includes doc.extracted_text, "Good evening."
      assert_not_includes doc.extracted_text, "00:01:27"
      assert_not_includes doc.extracted_text, "-->"
      assert doc.file.attached?, "Should attach the raw SRT file"
      assert doc.text_chars.positive?
      assert doc.fetched_at.present?
    end

    test "skips if meeting already has a transcript" do
      @meeting.meeting_documents.create!(
        document_type: "transcript",
        source_url: @video_url
      )

      stub_yt_dlp("dummy") do
        DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
      end

      assert_equal 1, @meeting.meeting_documents.where(document_type: "transcript").count
    end

    test "enqueues SummarizeMeetingJob when no minutes summary exists" do
      srt_content = "1\n00:00:01,000 --> 00:00:02,000\nHello.\n"

      stub_yt_dlp(srt_content) do
        assert_enqueued_with(job: SummarizeMeetingJob) do
          DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
        end
      end
    end

    test "does not enqueue SummarizeMeetingJob when minutes summary exists" do
      @meeting.meeting_summaries.create!(
        summary_type: "minutes_recap",
        generation_data: { "headline" => "test" }
      )
      srt_content = "1\n00:00:01,000 --> 00:00:02,000\nHello.\n"

      stub_yt_dlp(srt_content) do
        assert_no_enqueued_jobs(only: SummarizeMeetingJob) do
          DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
        end
      end
    end

    test "handles yt-dlp failure gracefully" do
      Open3.stub :capture3, ["", "ERROR: no captions", stub_status(false)] do
        Dir.stub :mktmpdir, "/tmp/test-transcript" do
          assert_nothing_raised do
            DownloadTranscriptJob.perform_now(@meeting.id, @video_url)
          end
        end
      end

      assert_equal 0, @meeting.meeting_documents.where(document_type: "transcript").count
    end

    private

    def stub_yt_dlp(srt_content)
      Dir.mktmpdir("test-transcript") do |tmpdir|
        srt_path = File.join(tmpdir, "video.en.srt")
        File.write(srt_path, srt_content)

        # Stub Open3.capture3 to succeed, and stub Dir.mktmpdir to use our tmpdir
        original_mktmpdir = Dir.method(:mktmpdir)

        Dir.define_singleton_method(:mktmpdir) do |*args, &block|
          if args.first == "transcript"
            block.call(tmpdir)
          else
            original_mktmpdir.call(*args, &block)
          end
        end

        Open3.stub :capture3, ["", "", stub_status(true)] do
          yield
        end
      ensure
        Dir.define_singleton_method(:mktmpdir, original_mktmpdir)
      end
    end

    def stub_status(success)
      status = Minitest::Mock.new
      status.expect :success?, success
      status
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/documents/download_transcript_job_test.rb`
Expected: FAIL (class not found)

- [ ] **Step 3: Implement DownloadTranscriptJob**

Create `app/jobs/documents/download_transcript_job.rb`:

```ruby
require "open3"

module Documents
  class DownloadTranscriptJob < ApplicationJob
    queue_as :default

    def perform(meeting_id, video_url)
      meeting = Meeting.find(meeting_id)

      # Idempotency: skip if transcript already exists
      return if meeting.meeting_documents.exists?(document_type: "transcript")

      srt_content = download_captions(video_url)
      return unless srt_content

      plain_text = parse_srt(srt_content)

      document = meeting.meeting_documents.create!(
        document_type: "transcript",
        source_url: video_url,
        extracted_text: plain_text,
        text_quality: "auto_transcribed",
        text_chars: plain_text.length,
        fetched_at: Time.current
      )

      document.file.attach(
        io: StringIO.new(srt_content),
        filename: "transcript-#{meeting.starts_at.to_date}.srt",
        content_type: "text/srt"
      )

      # Trigger preliminary summary if no minutes-based summary exists
      unless meeting.meeting_summaries.exists?(summary_type: "minutes_recap")
        SummarizeMeetingJob.perform_later(meeting.id)
      end
    end

    private

    def download_captions(video_url)
      Dir.mktmpdir("transcript") do |tmpdir|
        output_template = File.join(tmpdir, "video")

        stdout, stderr, status = Open3.capture3(
          "yt-dlp",
          "--write-auto-sub",
          "--sub-lang", "en",
          "--sub-format", "srt",
          "--skip-download",
          "-o", output_template,
          video_url
        )

        unless status.success?
          Rails.logger.error("DownloadTranscriptJob: yt-dlp failed for #{video_url}: #{stderr}")
          return nil
        end

        # yt-dlp writes to <output_template>.en.srt
        srt_path = Dir.glob(File.join(tmpdir, "*.srt")).first
        unless srt_path && File.exist?(srt_path)
          Rails.logger.error("DownloadTranscriptJob: No SRT file produced for #{video_url}")
          return nil
        end

        File.read(srt_path)
      end
    end

    def parse_srt(srt_content)
      srt_content
        .gsub(/^\d+\s*$/, "")                          # Remove sequence numbers
        .gsub(/^\d{2}:\d{2}:\d{2},\d{3}\s*-->.*$/, "") # Remove timestamp lines
        .gsub(/\n{3,}/, "\n\n")                         # Collapse multiple blank lines
        .strip
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/documents/download_transcript_job_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/jobs/documents/download_transcript_job.rb test/jobs/documents/download_transcript_job_test.rb
git commit -m "feat: add DownloadTranscriptJob to fetch YouTube auto-captions"
```

---

### Task 5: Update SummarizeMeetingJob for transcript support

**Files:**
- Modify: `app/jobs/summarize_meeting_job.rb:29-52`
- Modify: `test/jobs/summarize_meeting_job_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/jobs/summarize_meeting_job_test.rb`:

```ruby
test "generates meeting summary from transcript when no minutes exist" do
  @meeting.meeting_documents.create!(
    document_type: "transcript",
    source_url: "https://www.youtube.com/watch?v=test123",
    extracted_text: "Good evening. The council discussed the budget."
  )

  generation_data = {
    "source_type" => "transcript",
    "headline" => "Council discussed budget",
    "highlights" => [],
    "public_input" => [],
    "item_details" => []
  }

  mock_ai = Minitest::Mock.new
  mock_ai.expect :prepare_kb_context, "" do |arg|
    arg.is_a?(Array)
  end
  mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **kwargs|
    type == "transcript" && text.include?("council discussed the budget")
  end
  mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg|
    arg.is_a?(Hash)
  end
  mock_ai.expect :render_topic_summary, "## Summary" do |arg|
    arg.is_a?(String)
  end

  retrieval_stub = Object.new
  def retrieval_stub.retrieve_context(*args, **kwargs); []; end
  def retrieval_stub.format_context(*args); ""; end
  def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
  def retrieval_stub.format_topic_context(*args); []; end

  RetrievalService.stub :new, retrieval_stub do
    Ai::OpenAiService.stub :new, mock_ai do
      SummarizeMeetingJob.perform_now(@meeting.id)
    end
  end

  summary = @meeting.meeting_summaries.find_by(summary_type: "transcript_recap")
  assert summary, "Should create a transcript_recap summary"
  assert_equal "transcript", summary.generation_data["source_type"]
end

test "minutes take priority over transcript" do
  @meeting.meeting_documents.create!(
    document_type: "minutes_pdf",
    source_url: "http://example.com/minutes.pdf",
    extracted_text: "Official minutes text."
  )
  @meeting.meeting_documents.create!(
    document_type: "transcript",
    source_url: "https://www.youtube.com/watch?v=test123",
    extracted_text: "Transcript text with discussion."
  )

  generation_data = {
    "headline" => "Council approved the budget",
    "highlights" => [],
    "public_input" => [],
    "item_details" => []
  }

  mock_ai = Minitest::Mock.new
  mock_ai.expect :prepare_kb_context, "" do |arg|
    arg.is_a?(Array)
  end
  mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **kwargs|
    type == "minutes"
  end
  mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg|
    arg.is_a?(Hash)
  end
  mock_ai.expect :render_topic_summary, "## Summary" do |arg|
    arg.is_a?(String)
  end

  retrieval_stub = Object.new
  def retrieval_stub.retrieve_context(*args, **kwargs); []; end
  def retrieval_stub.format_context(*args); ""; end
  def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
  def retrieval_stub.format_topic_context(*args); []; end

  RetrievalService.stub :new, retrieval_stub do
    Ai::OpenAiService.stub :new, mock_ai do
      SummarizeMeetingJob.perform_now(@meeting.id)
    end
  end

  summary = @meeting.meeting_summaries.find_by(summary_type: "minutes_recap")
  assert summary, "Should create minutes_recap, not transcript_recap"
  assert_nil @meeting.meeting_summaries.find_by(summary_type: "transcript_recap")
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb -n "/transcript/"`
Expected: FAIL

- [ ] **Step 3: Update generate_meeting_summary to support transcript**

In `app/jobs/summarize_meeting_job.rb`, replace the `generate_meeting_summary` method (lines 18-53):

```ruby
def generate_meeting_summary(meeting, ai_service, retrieval_service)
  query = build_retrieval_query(meeting)
  retrieved_chunks = begin
    retrieval_service.retrieve_context(query)
  rescue => e
    Rails.logger.warn("Context retrieval failed for Meeting #{meeting.id}: #{e.message}")
    []
  end
  formatted_context = retrieval_service.format_context(retrieved_chunks).split("\n\n")
  kb_context = ai_service.prepare_kb_context(formatted_context)

  # Prefer minutes (authoritative) over transcript over packet
  minutes_doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf")
  if minutes_doc&.extracted_text.present?
    transcript_doc = meeting.meeting_documents.find_by(document_type: "transcript")
    doc_text = minutes_doc.extracted_text
    if transcript_doc&.extracted_text.present?
      doc_text += "\n\n--- Additional context from meeting recording transcript ---\n\n" +
                  transcript_doc.extracted_text.truncate(15_000)
    end

    json_str = ai_service.analyze_meeting_content(doc_text, kb_context, "minutes", source: meeting)
    result = save_summary(meeting, "minutes_recap", json_str)

    # Remove any preliminary transcript summary now that minutes are available
    meeting.meeting_summaries.where(summary_type: "transcript_recap").destroy_all

    # Track source type in generation_data
    if result&.generation_data.is_a?(Hash)
      source = transcript_doc&.extracted_text.present? ? "minutes_with_transcript" : "minutes"
      result.update!(generation_data: result.generation_data.merge("source_type" => source))
    end
    return
  end

  # Fall back to transcript
  transcript_doc = meeting.meeting_documents.find_by(document_type: "transcript")
  if transcript_doc&.extracted_text.present?
    json_str = ai_service.analyze_meeting_content(transcript_doc.extracted_text, kb_context, "transcript", source: meeting)
    result = save_summary(meeting, "transcript_recap", json_str)
    if result&.generation_data.is_a?(Hash)
      result.update!(generation_data: result.generation_data.merge("source_type" => "transcript"))
    end
    return
  end

  # Fall back to packet
  packet_doc = meeting.meeting_documents.where("document_type LIKE ?", "%packet%").first
  if packet_doc
    doc_text = if packet_doc.extractions.any?
      ai_service.prepare_doc_context(packet_doc.extractions)
    elsif packet_doc.extracted_text.present?
      packet_doc.extracted_text
    end

    if doc_text
      json_str = ai_service.analyze_meeting_content(doc_text, kb_context, "packet", source: meeting)
      save_summary(meeting, "packet_analysis", json_str)
    else
      Rails.logger.warn("No extractable text for packet document on Meeting #{meeting.id}")
    end
  end
end
```

- [ ] **Step 4: Update save_summary to return the record**

In `app/jobs/summarize_meeting_job.rb`, update the `save_summary` method to return the summary:

```ruby
def save_summary(meeting, type, json_str)
  generation_data = begin
    JSON.parse(json_str)
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse meeting summary JSON: #{e.message}"
    {}
  end

  summary = meeting.meeting_summaries.find_or_initialize_by(summary_type: type)
  summary.generation_data = generation_data
  summary.content = nil
  summary.save!
  summary
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb`
Expected: ALL PASS (both new and existing tests)

- [ ] **Step 6: Commit**

```bash
git add app/jobs/summarize_meeting_job.rb test/jobs/summarize_meeting_job_test.rb
git commit -m "feat: add transcript support to SummarizeMeetingJob

Transcript used as primary source when no minutes exist (produces
transcript_recap). When minutes arrive, transcript is appended as
supplementary context. Preliminary transcript summary is cleaned up
when minutes-based summary is generated."
```

---

### Task 6: Update MeetingsController and show view for transcript banner

**Files:**
- Modify: `app/controllers/meetings_controller.rb:23-25`
- Modify: `app/views/meetings/show.html.erb:35-37`

- [ ] **Step 1: Update controller to find transcript_recap summaries**

In `app/controllers/meetings_controller.rb`, update the summary lookup (line 23-25):

```ruby
# Prefer minutes_recap over transcript_recap over packet_analysis
@summary = @meeting.meeting_summaries.find_by(summary_type: "minutes_recap") ||
           @meeting.meeting_summaries.find_by(summary_type: "transcript_recap") ||
           @meeting.meeting_summaries.find_by(summary_type: "packet_analysis")
```

- [ ] **Step 2: Add transcript banner to the view**

In `app/views/meetings/show.html.erb`, after line 35 (`</div>` closing meeting-meta) and before line 37 (`<% gd = @summary&.generation_data.presence %>`), add:

```erb
<% if @summary&.generation_data&.dig("source_type") == "transcript" %>
  <div class="transcript-banner">
    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="12" cy="12" r="10"></circle>
      <line x1="12" y1="8" x2="12" y2="12"></line>
      <line x1="12" y1="16" x2="12.01" y2="16"></line>
    </svg>
    This summary is based on the meeting's video recording. It will be updated when official minutes are published.
  </div>
<% end %>
```

- [ ] **Step 3: Add CSS for the transcript banner**

Find the meeting-specific stylesheet. Add:

```css
.transcript-banner {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  padding: var(--space-sm) var(--space-md);
  margin-bottom: var(--space-lg);
  background-color: var(--color-cool-bg, #e8eef4);
  border: 1px solid var(--color-cool-border, #b0c4d8);
  border-radius: var(--radius-sm);
  font-family: var(--font-body);
  font-size: var(--text-sm);
  color: var(--color-cool-text, #2c3e50);
}

.transcript-banner svg {
  flex-shrink: 0;
  color: var(--color-cool-accent, #3a7bd5);
}
```

Note: Verify the exact CSS custom property names by checking the design system stylesheet. Use existing `--color-*` variables where available. The banner should be cool-toned and distinct from the warm cream background.

- [ ] **Step 4: Run the app and manually verify**

Run: `bin/dev`
Navigate to a meeting page. The banner won't show yet (no transcript summaries exist), but verify no visual regressions.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/meetings_controller.rb app/views/meetings/show.html.erb app/assets/stylesheets/
git commit -m "feat: add transcript banner to meeting show page

Shows an informational banner when the summary is based on the video
recording instead of official minutes. Automatically removed when
minutes arrive and the summary is regenerated."
```

---

### Task 7: Wire DiscoverTranscriptsJob into DiscoverMeetingsJob

**Files:**
- Modify: `app/jobs/scrapers/discover_meetings_job.rb:9-24`

- [ ] **Step 1: Add the trigger at the end of perform**

In `app/jobs/scrapers/discover_meetings_job.rb`, update the `perform` method:

```ruby
def perform(since: nil)
  since ||= DEFAULT_LOOKBACK.ago
  agent = Mechanize.new
  agent.user_agent_alias = "Mac Safari"
  page = agent.get(MEETINGS_URL)

  loop do
    should_continue = parse_page(page, since)
    break unless should_continue

    next_link = page.link_with(text: /next ›/)
    break unless next_link

    page = next_link.click
  end

  # Check for YouTube transcripts for recent council meetings
  Scrapers::DiscoverTranscriptsJob.perform_later
end
```

- [ ] **Step 2: Run existing discover meetings tests to verify no regression**

Run: `bin/rails test test/jobs/scrapers/`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add app/jobs/scrapers/discover_meetings_job.rb
git commit -m "feat: trigger transcript discovery after meeting discovery"
```

---

### Task 8: Add document section support for transcript in show view

**Files:**
- Modify: `app/views/meetings/show.html.erb:204-237` (Documents section)

- [ ] **Step 1: Update the documents section to handle transcript display**

In the Documents section of `app/views/meetings/show.html.erb`, update the document list item (around line 210-229) to handle transcripts:

```erb
<% @meeting.meeting_documents.each do |doc| %>
  <li>
    <div>
      <span class="document-type"><%= doc.document_type.humanize %></span>
      <% if doc.file.attached? && doc.document_type.include?("pdf") %>
        <span class="document-meta">
          (<%= number_to_human_size(doc.file.byte_size) %>)
          <% if doc.text_quality.present? %>
            - Quality: <%= doc.text_quality.humanize %>
          <% end %>
        </span>
      <% elsif doc.document_type == "transcript" %>
        <span class="document-meta">
          (<%= number_to_human_size(doc.text_chars || 0) %> chars)
          - Source: Video Recording
        </span>
      <% end %>
    </div>
    <div>
      <% if doc.file.attached? && doc.document_type.include?("pdf") %>
        <%= link_to "Download PDF", rails_blob_path(doc.file, disposition: "attachment"), class: "btn btn--secondary btn--sm" %>
      <% elsif doc.document_type == "transcript" && doc.source_url.present? %>
        <%= link_to "Watch Recording", safe_external_url(doc.source_url), target: "_blank", rel: "noopener", class: "btn btn--secondary btn--sm" %>
      <% else %>
        <%= link_to "View Original", safe_external_url(doc.source_url), target: "_blank", rel: "noopener", class: "btn btn--secondary btn--sm" %>
      <% end %>
    </div>
  </li>
<% end %>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/meetings/show.html.erb
git commit -m "feat: show transcript document with Watch Recording link in documents section"
```

---

### Task 9: Run full test suite and lint

- [ ] **Step 1: Run full test suite**

Run: `bin/rails test`
Expected: ALL PASS

- [ ] **Step 2: Run linter**

Run: `bin/rubocop`
Expected: No new offenses. Fix any that appear in files you modified.

- [ ] **Step 3: Run CI checks**

Run: `bin/ci`
Expected: PASS

- [ ] **Step 4: Fix any issues found, then commit fixes**

If any fixes needed:
```bash
git add -A
git commit -m "fix: address lint/test issues from transcript feature"
```

---

### Task 10: Create PR

- [ ] **Step 1: Push branch and create PR**

```bash
git push -u origin feature/youtube-transcript-ingestion
gh pr create --title "Add YouTube transcript ingestion for same-day council meeting summaries" --body "$(cat <<'EOF'
## Summary
- Ingests YouTube auto-generated captions from council meeting recordings
- Produces same-day preliminary summaries when official minutes aren't available yet
- Enriches minutes-based summaries with transcript context when minutes arrive
- Shows a visible banner on meeting pages when summary is transcript-sourced

## Design
See `docs/superpowers/specs/2026-04-09-youtube-transcript-ingestion-design.md`

## Changes
- **New jobs:** `DiscoverTranscriptsJob` (finds YouTube videos for recent council meetings), `DownloadTranscriptJob` (fetches auto-captions, creates MeetingDocument)
- **Modified:** `SummarizeMeetingJob` (transcript priority tier, supplementary context), `DiscoverMeetingsJob` (triggers transcript discovery), `MeetingsController` (finds transcript summaries), meeting show view (transcript banner + document display)
- **Infrastructure:** `yt-dlp` added to Dockerfile

## Test plan
- [ ] Run `bin/rails test` — all tests pass
- [ ] Run `bin/ci` — lint, security, audit all pass
- [ ] Manually test with a real YouTube video ID to verify yt-dlp caption download works
- [ ] Verify transcript banner renders correctly on meeting show page
- [ ] Verify banner disappears when minutes-based summary exists

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
