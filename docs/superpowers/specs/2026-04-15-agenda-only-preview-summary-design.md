# Agenda-Only Preview Summary — Design

**Date:** 2026-04-15
**Status:** Draft
**Related:** Gap discovered when meeting 173 (Advisory Recreation Board, 2026-04-15) had an agenda PDF but no summary. Root cause: `SummarizeMeetingJob` requires a packet, minutes, or transcript document; agenda-only meetings fall off the end of the fallback chain.

## Problem

Committee meetings often publish an agenda but never a packet (minutes may come weeks later). For these meetings, residents see an empty summary section even though the agenda PDF has been scraped and its titles/descriptions have been text-extracted. The pipeline today:

1. No documents → no summary (correct)
2. Agenda only → **no summary** (broken — this spec)
3. Agenda + packet → packet-based summary (works)
4. Packet arrives after agenda → packet-based summary supersedes agenda (broken — this spec)
5. Minutes arrive → minutes-based summary supersedes all priors (works)

Data snapshot on 2026-04-15: 150 meetings have `agenda_pdf` with text; only 59 have `packet_pdf`. 91 meetings — more than half — are currently summary-less despite having extractable agenda content.

## Goals

- Generate a meeting-level preview summary when an `agenda_pdf` is available and no higher-tier source exists.
- Refresh forward-looking topic briefings (`TopicBriefing.headline`, `upcoming_headline`, `what_to_watch`) when a new agenda adds scheduled activity to an approved topic.
- Preserve the existing supersede chain so later documents (packet, transcript, minutes) overwrite earlier tiers cleanly.
- Do not generate retrospective artifacts (per-meeting `TopicSummary`, hollow-appearance pruning, knowledge extraction) from an agenda — those are meaningless for a meeting that hasn't happened.
- Preserve all existing `:full` mode behavior. Every current caller of `SummarizeMeetingJob` keeps working unchanged.

## Non-Goals

- Changing the prompt schema or editorial voice.
- Introducing a separate preview-only job. One job with a mode flag keeps the summarization pipeline legible in one place.
- Backfilling existing agenda-only meetings automatically. Optional rake task; the pipeline self-heals for new meetings.
- Rendering changes beyond a small label distinguishing agenda previews from packet previews. (See "Open UI detail" below.)

## Architecture

### Supersede tiers (new lowest tier)

```
minutes_recap      (priority 1 — authoritative)
transcript_recap   (priority 2 — when no minutes)
packet_analysis    (priority 3 — preview from packet)
agenda_preview     (priority 4 — preview from agenda, NEW)
(none)             (no documents available)
```

Each higher tier destroys all lower tiers when it's generated. `find_or_initialize_by(summary_type: …)` is used within a tier so agenda re-runs overwrite in place when the source PDF's SHA changes.

### `SummarizeMeetingJob` modes

Signature change:
```ruby
def perform(meeting_id, mode: :full)
```

All existing callers — `analyze_pdf_job` (packet/minutes branches), `ocr_job`, `download_transcript_job`, `admin/summaries_controller`, `lib/tasks/*.rake` — pass no mode arg and hit `:full` path. Behavior unchanged.

**`:full` mode** — current 4-step flow:
1. Meeting-level summary (minutes > transcript > packet priority).
2. Topic summaries (per approved topic, each also enqueues `GenerateTopicBriefingJob`).
3. `PruneHollowAppearancesJob`.
4. `ExtractKnowledgeJob`.

**`:agenda_preview` mode** — new:
1. Meeting-level summary from `agenda_pdf.extracted_text`. Return silently if `meeting.meeting_documents.find_by(document_type: "agenda_pdf")&.extracted_text` is blank.
2. For each approved topic appearing on this agenda, enqueue `GenerateTopicBriefingJob.perform_later(topic_id:, meeting_id:)` — standalone pass, no `TopicSummary` generated.
3. Skip `PruneHollowAppearancesJob` (no `activity_level` signals to prune against).
4. Skip `ExtractKnowledgeJob` (no authoritative content to extract).

### Trigger point

`Documents::AnalyzePdfJob` currently branches on `document_type` after text extraction completes:
- `packet*` → `SummarizeMeetingJob.perform_later(meeting_id)` (immediate)
- `minutes_pdf` → `SummarizeMeetingJob.set(wait: 10.minutes).perform_later(meeting_id)` (after extraction/triage)

Add new branch:
- `agenda_pdf` → `SummarizeMeetingJob.set(wait: 5.minutes).perform_later(meeting_id, mode: :agenda_preview)`

5-minute delay lets `ParseAgendaJob` (from the parallel `agenda_html` download) → `ExtractTopicsJob` → `AutoTriageJob` (3-minute delay) complete first. When the preview job fires, topic briefings refresh against already-approved topics.

### Source selection

Only `agenda_pdf` is used. Data confirms `agenda_html` has `extracted_text` populated in 0/150 meetings — HTML docs are parsed structurally by `ParseAgendaJob` but never feed content to the AI. No fallback path needed.

If `agenda_pdf` exists but `extracted_text` is blank (extraction failure, OCR pending), the job returns without creating a summary. When OCR or re-analysis eventually populates text, `analyze_pdf_job` will re-trigger summarization.

### `MeetingSummary` model

Validator inclusion list extended:
```ruby
validates :summary_type, inclusion: { in: %w[minutes_recap transcript_recap packet_analysis agenda_preview] }
```

No schema migration required — `summary_type` is already a string column.

`generation_data` fields on an agenda preview:
- `source_type: "agenda"` (new value joining existing `"minutes"`, `"transcript"`, `"minutes_with_transcript"`, `"packet"`)
- `framing: "preview"` or `"stale_preview"` (reuses existing `compute_framing` logic — future meetings get `"preview"`, past meetings with no packet/minutes get `"stale_preview"`)

### Supersede cleanup in `generate_meeting_summary`

Current cleanup:
- **Minutes path** (priority 1): `destroy_all` on `transcript_recap`, `packet_analysis`.
- **Transcript path** (priority 2): `destroy_all` on `packet_analysis`.
- **Packet path** (priority 3): no cleanup.

Updated cleanup:
- **Minutes path**: add `agenda_preview` to destroy list.
- **Transcript path**: add `agenda_preview` to destroy list.
- **Packet path**: add `destroy_all` on `agenda_preview`.
- **Agenda path** (new, priority 4): no cleanup — bottom of stack.

### Prompt template

Single database-driven `analyze_meeting_content` template. The template uses simple `{{placeholder}}` interpolation — no conditional directives. Behavior branching is narrative: the prompt already instructs the AI to switch framing based on the interpolated `{{type}}` and `{{temporal_framing}}` values (see existing `stale_preview` paragraph).

Extend the existing narrative-conditional section with an agenda-specific block, following the same pattern:

```
If the source {{type}} is "agenda":
- You are seeing agenda titles and brief item descriptions only — not
  full packet body text. Apply extra restraint.
- Do not infer what will be discussed beyond what titles and descriptions
  state.
- item_details entries should be 1 short sentence each; omit items whose
  title gives nothing substantive to work with.
- highlights may be empty; do not manufacture impact statements from titles
  alone.
- The headline should reflect what's scheduled, not what might happen.
```

The AI reads the interpolated `{{type}}` value and applies the matching block, just as it does today for `{{temporal_framing}}` values of `"preview"` / `"recap"` / `"stale_preview"`.

Delivered via `prompt_templates:populate` after code deploy (standard pattern, auto-creates `PromptVersion` rollback row).

Existing prompt language already accommodates "agenda" as a source word — see the `stale_preview` block: "based on the agenda/packet. Do not infer outcomes." The new block tightens that further for agenda-only inputs.

### `Ai::OpenAiService#analyze_meeting_content`

No signature change. Called with `type: "agenda"` from the new mode. Existing `temporal_framing` logic continues to work:
- Future meeting → `"preview"`
- Past meeting → `"stale_preview"` (since type is not `"minutes"` or `"transcript"`)

## What the resident sees

Meeting show page renders `agenda_preview` summaries through the existing `MeetingSummary.generation_data` structured rendering path (`MeetingsHelper#meeting_headline`, `meeting_highlights`, etc.). No template fork required.

A small tagged label distinguishes agenda previews from packet previews. Matches existing transcript banner pattern:
- `source_type == "agenda"` → "Preview based on the posted agenda. This meeting hasn't happened yet — check back for a full recap after minutes are published."
- `source_type == "packet"` → (existing behavior)

Open UI detail: whether this lives as a banner (like transcript), a prefix on the headline, or a `dateline`-style eyebrow. Decide during implementation; follows existing visual patterns for source attribution.

## Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| Existing `SummarizeMeetingJob` callers break from signature change. | Default `mode: :full` keyword arg. All callers unchanged. |
| Topic briefings regenerate with thin agenda context and degrade quality. | `GenerateTopicBriefingJob` already runs from `:full` mode per meeting; its prompt handles mixed-tier context. Agenda-triggered briefing refresh is an additive input, not a replacement. |
| Agenda preview with no substantive content produces empty/garbage output. | Prompt restraint clause allows empty `highlights` / minimal `item_details`. If `extracted_text.blank?`, job returns silently — no row created. |
| Packet arrival after agenda leaves stale `agenda_preview` visible. | Packet path adds `destroy_all` on `agenda_preview`. |
| Agenda PDF updates (SHA change) don't re-summarize. | `analyze_pdf_job` re-runs on SHA change → re-enqueues `SummarizeMeetingJob` in agenda_preview mode → `find_or_initialize_by` overwrites the existing row. |
| Prompt template change breaks minutes/transcript/packet outputs. | Conditional is scoped to `type == "agenda"` only. Existing paths unaffected. |

## Testing

**New tests:**
- `SummarizeMeetingJob` with `mode: :agenda_preview`:
  - Generates meeting summary with `summary_type: "agenda_preview"`, `source_type: "agenda"`.
  - Does NOT create `TopicSummary` records.
  - Enqueues `GenerateTopicBriefingJob` for each approved topic on the meeting.
  - Does NOT enqueue `PruneHollowAppearancesJob` or `ExtractKnowledgeJob`.
  - Returns silently if `agenda_pdf` is absent or has blank `extracted_text`.
- Supersede cleanup:
  - Packet run destroys any pre-existing `agenda_preview`.
  - Transcript run destroys `agenda_preview`.
  - Minutes run destroys `agenda_preview`.
- Validator: `summary_type: "agenda_preview"` accepted.
- `analyze_pdf_job` with `agenda_pdf`: enqueues `SummarizeMeetingJob` with `mode: :agenda_preview` and 5-minute delay.

**Regression tests (must continue passing):**
- All 16 existing `SummarizeMeetingJob` test cases unchanged.
- Existing packet / minutes / transcript supersede behavior.
- `MeetingSummary` validations on existing `summary_type` values.

## Backfill (optional follow-up)

One-off rake task `agenda_previews:backfill`:
```ruby
Meeting.joins(:meeting_documents)
  .where(meeting_documents: { document_type: "agenda_pdf" })
  .where.missing(:meeting_summaries)
  .distinct
  .find_each do |m|
    SummarizeMeetingJob.perform_later(m.id, mode: :agenda_preview)
  end
```

Estimated ~90 meetings. Low priority — pipeline self-heals for new meetings.

## Implementation order

1. Add `"agenda_preview"` to `MeetingSummary` validator + test.
2. Refactor `SummarizeMeetingJob` to accept `mode:` kwarg; keep `:full` behavior identical.
3. Implement `:agenda_preview` branch: meeting summary + briefing enqueue.
4. Add cleanup in packet/transcript/minutes paths.
5. Add trigger in `analyze_pdf_job` for `agenda_pdf`.
6. Update prompt template seed data with agenda-specific restraint block.
7. UI label for `source_type == "agenda"` on meeting show page.
8. Deploy: `kamal deploy` → `prompt_templates:populate`.
9. (Optional) Run backfill rake task.

## Open questions (to resolve during implementation)

- UI label treatment (banner vs headline prefix vs eyebrow) — pick during implementation to match existing visual patterns.
- Whether the 5-minute delay is sufficient for `AutoTriageJob` (3-min delay) to complete plus topic extraction time. If briefings regularly fire against unapproved topics, bump delay to 7-10 minutes.
