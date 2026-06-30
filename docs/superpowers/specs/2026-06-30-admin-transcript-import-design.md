# Admin Transcript Import Workflow Design

## Purpose

Create an admin tool for importing YouTube captions for an existing meeting and running the follow-up work needed to make the transcript useful across the site.

The tool replaces the current CLI-only workflow:

```ruby
Documents::DownloadTranscriptJob.perform_now(meeting_id, youtube_url)
Topics::MeetingReanalysisService.new(meeting_id).call
```

with a background workflow started from `/admin/transcript_imports`.

## User Experience

Add a global admin page at `/admin/transcript_imports`.

The page uses a two-column layout:

- Main column:
  - Meeting selector for existing meetings.
  - Optional lightweight text filter for narrowing meetings by title, body, date, or ID.
  - YouTube URL field.
  - `Check URL` action that validates the URL and tries to confirm caption availability without creating records.
  - `Begin Import` submit button.
  - Recent/running transcript import workflows table.
- Sidebar column:
  - Short explanation of what the job does.
  - Note that the workflow logs each step and captures failure details.

Page lede:

> Import YouTube captions for a meeting, generate or refresh its summary, and reanalyze related topics in one background workflow.

The form should not use fake progress pills or decorative status indicators that do not reflect real state.

## Workflow Behavior

Submitting the form creates a persisted transcript import record and enqueues one workflow job.

The workflow job performs these steps:

1. Validate the meeting exists.
2. Validate the YouTube URL shape.
3. Download available English captions using the existing transcript download behavior.
4. Store a transcript `MeetingDocument` with the raw SRT attached and extracted plain text.
5. Generate or refresh the meeting summary as appropriate.
6. Run `Topics::MeetingReanalysisService` for the meeting.
7. Record completion details, including affected topic IDs.

Temporary caption download files should remain scoped to `Dir.mktmpdir { ... }` so they are automatically cleaned up when the download block exits. The workflow should not leave additional temporary files behind.

## URL Precheck

`Check URL` should be a non-destructive admin action.

It should:

- Validate the URL format accepted by the transcript downloader.
- Attempt a lightweight `yt-dlp` subtitle/caption metadata check for English captions.
- Report one of these outcomes:
  - URL is invalid.
  - URL appears valid and English captions are available.
  - URL appears valid but no English captions were found.
  - This server could not verify captions, likely because YouTube blocked or rate-limited the request.

The precheck must not create `MeetingDocument`, `TranscriptImport`, meeting summary, or topic records.

## Data Model

Add a persisted `TranscriptImport` model to support the admin status table and troubleshooting.

Recommended fields:

- `meeting: references`
- `youtube_url: string`
- `status: string` with values such as `queued`, `running`, `completed`, `failed`
- `started_at: datetime`
- `finished_at: datetime`
- `meeting_document_id: bigint`, nullable
- `affected_topic_ids: json`, default empty array
- `step_logs: json`, default empty array
- `error_class: string`, nullable
- `error_message: text`, nullable
- `error_backtrace: text`, nullable
- timestamps

`step_logs` should contain compact structured entries, for example:

```json
{
  "at": "2026-06-30T12:34:56Z",
  "level": "info",
  "step": "download_transcript",
  "message": "Downloaded transcript",
  "metadata": { "meeting_document_id": 123, "text_chars": 45678 }
}
```

## Logging and Troubleshooting

The workflow job should log to both Rails logs and the `TranscriptImport` record.

Each major step should record:

- transcript import ID
- meeting ID
- YouTube URL
- step name
- success/failure message
- useful metadata, such as document ID, transcript character count, summary status, and affected topic IDs

On failure, the job should:

- set status to `failed`
- record `finished_at`
- store exception class, message, and backtrace
- append a final error step log
- emit a Rails error log with the same identifying context

Failures should be visible from `/admin/transcript_imports` without needing SSH access to server logs.

## Controllers and Routes

Add admin routes under the existing admin scope:

- `GET /admin/transcript_imports` — show form and recent workflows
- `POST /admin/transcript_imports` — create workflow record and enqueue job
- `POST /admin/transcript_imports/check_url` — run non-destructive URL precheck

The controller should inherit from `Admin::BaseController` so existing admin and MFA requirements apply.

## Jobs and Services

Add a dedicated workflow job, for example `Admin::TranscriptImportWorkflowJob`.

The job should coordinate existing services/jobs rather than duplicating business logic. If the existing `Documents::DownloadTranscriptJob` does not expose enough return information for logging, refactor the shared download/store behavior into a small service that both jobs can call.

The workflow should avoid racing topic reanalysis against summary generation. If summary generation remains asynchronous, the workflow must make that clear in its status/logs. Prefer a deterministic flow for the admin-triggered job so completion means the import and topic reanalysis have actually finished.

## Validation and Idempotency

The create action should reject:

- missing meeting ID
- unknown meeting ID
- invalid YouTube URL

The workflow should handle existing transcript documents safely. If the meeting already has a transcript, the job should not create a duplicate. It should record a clear log entry, reuse the existing transcript document for downstream summary/topic work, and complete successfully unless another step fails. The admin page should make this visible in the workflow logs so the operator understands why no new transcript document was created.

## Testing

Add integration/controller tests for:

- admin auth/MFA protection through `Admin::BaseController`
- rendering the transcript import page
- creating a workflow record and enqueuing the workflow job
- invalid meeting and invalid URL handling
- URL precheck outcomes with command/service stubs

Add job tests for:

- successful workflow logging and status transitions
- transcript document creation/reuse behavior
- topic reanalysis invocation
- failed download/error status and stored error details
- temp file cleanup through the existing `Dir.mktmpdir` download boundary

## Out of Scope

- A public-facing transcript import UI.
- Replacing official minutes or source documents with AI output.
- A large JavaScript autocomplete framework.
- Real-time live progress updates. The initial version can show status after refresh.
