# Admin Transcript SRT Upload Design

## Goal

Allow an admin to recover from failed YouTube transcript imports by uploading a local `.srt` transcript file on the existing `/admin/transcript_imports` page. The YouTube URL remains required for provenance, but an uploaded SRT file overrides the YouTube caption download step.

## Current Context

The existing admin transcript import form accepts a meeting and YouTube watch URL. It creates a `TranscriptImport`, queues `Admin::TranscriptImportWorkflowJob`, downloads captions through `Documents::TranscriptDownloader`, stores a `MeetingDocument` of `document_type: "transcript"`, then reruns meeting summary generation, hollow appearance pruning, and topic reanalysis.

This design keeps that workflow and adds one alternate transcript source for the first step.

## User Experience

The existing form gains one optional file input labeled `SRT transcript file (optional)`.

Copy near the input states: `If an SRT is uploaded, it will be used instead of YouTube captions. The YouTube URL is still saved as the source video.`

When an admin chooses a file, the page shows a `Remove file` button before submission. Clicking it clears the selected file and hides or disables the remove control, so the admin can submit the form using YouTube captions instead.

The existing `Check URL` button remains scoped to YouTube availability. It does not validate the uploaded file because file inputs cannot be preserved across redirects and the check is only a YouTube preflight.

## Data Model

`TranscriptImport` should retain its required `youtube_url` field. Add an Active Storage attachment for the optional uploaded SRT file, for example `has_one_attached :srt_file`.

The uploaded file is attached to the `TranscriptImport` when the workflow is queued. This keeps the original upload available to the background job and preserves enough audit trail to understand which source was used.

No separate source mode column is required for the initial implementation. The source is determined by whether `transcript_import.srt_file.attached?` is true.

## Import Workflow

`Admin::TranscriptImportWorkflowJob` branches during the transcript acquisition step:

- If `transcript_import.srt_file` is attached, store that SRT as the meeting transcript and skip `yt-dlp`.
- If no SRT is attached, use the existing `Documents::TranscriptDownloader` path unchanged.

Both paths should return a small result object with the stored `MeetingDocument`, a status such as `created` or `reused`, and a source label such as `uploaded_srt` or `youtube_captions`, so the job can log clear workflow messages without duplicating storage logic.

## Uploaded SRT Storage

Introduce a focused service, for example `Documents::UploadedTranscriptImporter`, responsible for taking a meeting, YouTube URL, and attached SRT file and creating the transcript `MeetingDocument`.

The service should:

- Read the uploaded SRT content from Active Storage.
- Parse plain transcript text with the same SRT-stripping behavior used by `Documents::TranscriptDownloader`.
- Reject blank or unparsable transcript text with a clear error.
- Replace any existing transcript document for that meeting, matching the current downloader behavior when a usable transcript is not reused.
- Create a `MeetingDocument` with `document_type: "transcript"`, `source_url: youtube_url`, `text_quality: "uploaded_transcript"`, `extracted_text`, `text_chars`, and `fetched_at`.
- Attach the original SRT content to `MeetingDocument.file` with an `.srt` filename and `text/srt` content type.

## Validation and Errors

The controller continues to require a valid meeting and a valid YouTube watch URL.

When a file is uploaded, the controller should perform light validation before queueing:

- File extension should be `.srt`.
- Content type may be accepted as `text/srt`, `application/x-subrip`, `text/plain`, or `application/octet-stream`, because browser uploads vary.
- Empty files should be rejected if size is available.

Deep parsing validation belongs in the workflow service so failures are logged consistently in `TranscriptImport` step logs.

On failure, the existing workflow failure behavior should mark the import failed and show the error in recent workflow logs.

## Tests

Add or update tests for:

- Admin form renders the optional SRT upload field, explanatory note, and remove-file UI.
- Controller accepts a valid `.srt` upload with a valid YouTube URL and queues the workflow.
- Controller rejects obviously invalid upload types while preserving meeting and URL form values.
- Workflow uses the uploaded SRT path when an attachment is present and does not call the YouTube downloader.
- Uploaded SRT service stores a transcript `MeetingDocument`, attaches the SRT, extracts text, and records the YouTube URL as `source_url`.
- Workflow logs identify uploaded SRT usage.
- Existing YouTube-only import tests continue to pass.

## Out of Scope

- Supporting transcript formats other than `.srt`.
- Editing transcript text in the browser.
- Preserving an uploaded file across the `Check URL` redirect.
- Adding a separate upload history page.
