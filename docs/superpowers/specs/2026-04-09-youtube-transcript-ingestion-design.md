# YouTube Transcript Ingestion Design

**Date:** 2026-04-09
**Status:** Approved

## Problem

Council meetings and work sessions are recorded and posted to YouTube within hours, but the site currently waits weeks for official minutes before publishing summaries. Residents get nothing in the gap.

## Solution

Ingest YouTube auto-generated captions as a new `transcript` document type. Use transcripts to produce same-day preliminary summaries, then enrich the authoritative minutes-based summaries with transcript context when minutes arrive later.

**Core principle:** The transcript is a **supplement**, not a replacement. It never overrides official sources. The existing pipeline is untouched unless a transcript happens to be available.

## Data Model

### MeetingDocument

No new tables or columns. Transcripts use the existing `meeting_documents` table:

| Field | Value |
|-------|-------|
| `document_type` | `"transcript"` |
| `source_url` | YouTube video URL (e.g., `https://www.youtube.com/watch?v=S8rW22zizHc`) |
| `extracted_text` | Plain text (SRT timestamps stripped) |
| `file` | Raw SRT file (Active Storage attachment) |
| `fetched_at` | When the transcript was downloaded |
| `text_chars` | Character count of extracted text |
| `text_quality` | `"auto_transcribed"` |

### Meeting#document_status

Updated priority: `:minutes` > `:packet` > `:transcript` > `:agenda` > `:none`.

### MeetingSummary.generation_data

New `source_type` key in the existing JSON column:
- `"transcript"` — preliminary summary from transcript only
- `"minutes"` — authoritative summary from minutes only
- `"minutes_with_transcript"` — authoritative summary enriched with transcript context

## Job Chain

### Scrapers::DiscoverTranscriptsJob

**Trigger:** Enqueued by `DiscoverMeetingsJob` at the end of its run.

**Logic:**
1. Query for Meeting records where:
   - `body_name` matches Council or Work Session (the only recorded meetings)
   - `starts_at` within the last 48 hours
   - No existing `transcript` document
2. Call `yt-dlp --flat-playlist --print "%(id)s | %(title)s"` on the channel URL
3. Parse each video title with regex to extract the meeting date:
   - Primary pattern: `/for \w+, (.+)$/` (handles "Two Rivers City Council Meeting for Monday, April 6, 2026")
   - Unmatched titles are logged as warnings and skipped
4. Match parsed date + body keyword ("Council", "Work Session") to Meeting records
5. Enqueue `Documents::DownloadTranscriptJob` for each match

**Channel URL constant:**
```ruby
YOUTUBE_CHANNEL_URL = "https://www.youtube.com/@Two_Rivers_WI/streams"
```

**Idempotency:** Skips meetings that already have a transcript document.

### Documents::DownloadTranscriptJob

**Input:** Meeting ID, YouTube video URL.

**Logic:**
1. Check for existing transcript document on the meeting (idempotency guard)
2. Call `yt-dlp --write-auto-sub --sub-lang en --sub-format srt --skip-download` via `Open3.capture3`
3. Parse SRT to plain text: strip sequence numbers, timestamps (`HH:MM:SS,mmm --> HH:MM:SS,mmm`), blank lines
4. Create `MeetingDocument` with `document_type: "transcript"`:
   - Attach raw SRT file
   - Store plain text in `extracted_text`
   - Set `text_quality: "auto_transcribed"`, `text_chars`, `fetched_at`, `source_url`
5. If the meeting has no minutes-based summary yet, enqueue `SummarizeMeetingJob(meeting.id)`

**Shell execution:** `Open3.capture3` pattern, consistent with `pdftotext`/`tesseract` usage in existing jobs. Uses `Dir.mktmpdir` for `yt-dlp` output files, cleaned up after processing.

**Failure handling:** Log error and exit on `yt-dlp` failure. Next day's discovery run retries automatically.

## Summarization Changes

### SummarizeMeetingJob

**Updated document priority:** minutes > transcript > packet.

**When transcript is the best available source (no minutes):**
- Use transcript `extracted_text` as primary input
- Adjust AI prompt: "Summarize the discussion from this meeting recording transcript" (vs. "Summarize the official minutes")
- Store `"source_type": "transcript"` in `MeetingSummary.generation_data`
- The resulting summary is preliminary — accurate to the recording but not the official record

**When minutes arrive and re-trigger the job:**
- Minutes remain primary input (existing behavior unchanged)
- Transcript `extracted_text` appended as supplementary context: "Additional context from the meeting recording transcript" (15K char limit)
- Store `"source_type": "minutes_with_transcript"` in `generation_data`
- If no transcript exists, behavior is identical to today (`"source_type": "minutes"`)

**No changes to other extraction jobs.** `ExtractTopicsJob`, `ExtractVotesJob`, and `ExtractCommitteeMembersJob` continue to trigger only from minutes/agenda.

## Meeting Show Page — Transcript Banner

**Condition:** `MeetingSummary` exists with `generation_data["source_type"] == "transcript"` and no `minutes_pdf` document on the meeting.

**Location:** Top of meeting show page, between the meeting meta section and the headline section.

**Appearance:** A distinct, noticeable callout — NOT the warm theme (too subtle against the cream background). Use a cool or contrasting accent treatment so it reads as informational/cautionary:

> This summary is based on the meeting's video recording. It will be updated when official minutes are published.

**Removal:** Automatic. When minutes arrive and `SummarizeMeetingJob` regenerates the summary with `source_type: "minutes"` or `"minutes_with_transcript"`, the banner condition is no longer met. No manual action required.

## Infrastructure

### Dockerfile

Add `yt-dlp` as a system dependency. Download the standalone binary (no Python required):

```dockerfile
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp && \
    chmod +x /usr/local/bin/yt-dlp
```

### Schedule

No new entry in `config/recurring.yml`. `DiscoverTranscriptsJob` is enqueued by `DiscoverMeetingsJob` (daily at 11pm). The chain is:

```
DiscoverMeetingsJob (11pm daily)
  → at end of run, enqueues DiscoverTranscriptsJob
    → for each matched video, enqueues DownloadTranscriptJob
      → if no minutes summary, enqueues SummarizeMeetingJob
```

## Scope Boundaries

**In scope:**
- Two new jobs (discover + download)
- `SummarizeMeetingJob` modifications (transcript priority, supplementary context, source_type tracking)
- `Meeting#document_status` update
- Transcript banner on meeting show page
- Dockerfile update for `yt-dlp`
- `DiscoverMeetingsJob` change to enqueue transcript discovery

**Out of scope:**
- Speaker diarization / attribution
- Vote or member extraction from transcripts
- Admin UI for manual video-to-meeting linking
- Backfilling old videos (manual rake task, future work)
- Whisper / local transcription (YouTube auto-captions are sufficient)
- Video download or storage (captions only, `--skip-download`)

## YouTube Title Matching

Observed title patterns from the channel (`@Two_Rivers_WI/streams`):

| Pattern | Example | Frequency |
|---------|---------|-----------|
| Standard | `Two Rivers City Council Meeting for Monday, April 6, 2026` | ~90% |
| Work Session | `Two Rivers City Council Work Session for Monday, March 30, 2026` | ~8% |
| Special | `Joint Meeting of Plan Commission, EAB, Advisory Recreation Board, & City Council 7/23/2025` | ~2% |

The regex handles the standard and work session patterns. Special/joint meeting titles are logged and skipped. The discovery job only looks for videos matching meetings in the last 48 hours, not the full back-catalog.
