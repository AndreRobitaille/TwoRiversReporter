# Issue 49 Plan: Topic-aware summarization (governance-compliant)

Goal: make meeting summaries explicitly topic-aware and compliant with `docs/topics/TOPIC_GOVERNANCE.md`, separating factual record, institutional framing, and civic sentiment with citations.

References:
- docs/DEVELOPMENT_PLAN.md
- docs/topic-first-migration-plan.md
- docs/topics/TOPIC_GOVERNANCE.md

## Current State (code + behavior)
- Meeting-centric summaries only (SummarizeMeetingJob + Ai::OpenAiService).
- Summaries are stored as MeetingSummary records with summary_type (minutes_recap, packet_analysis).
- Retrieval context is meeting-based query against KnowledgeChunk (RetrievalService).
- Packet summaries can include page citations when extractions are available.

## Gaps vs Topic Governance
- No explicit separation of factual record vs institutional framing vs civic sentiment.
- Summary output does not surface topic continuity or recurrence.
- Retrieval context is meeting-centric and not scoped by topic history.
- Topic canonical names/aliases are not used in summaries.

## Objectives (Issue 49)
- Summaries are topic-aware and organized by Topic continuity.
- Factual claims include citations to meeting documents or agenda pages when available.
- Framing is labeled as institutional perspective, not truth.
- Civic sentiment is explicitly observational, not factual.
- Summaries highlight recurrence, deferral, and cross-body progression when evidenced.

## Constraints (Topic Governance)
- Never assign motive or intent.
- Do not state facts without document evidence.
- Explicitly separate factual record, institutional framing, and civic sentiment.
- Prefer agenda anchors; note absence or ambiguity.
- External/community-sourced signals must be labeled as resident-reported and not treated as factual record.

## Proposed Output Contract (LLM JSON)

### Input context assembly
- Meeting documents:
  - Minutes text (if available) for decisions/votes.
  - Packet extractions with page numbers for citations.
- Agenda items linked to topics (agenda_item_topics + topic_appearances).
- Topic continuity signals from TopicStatusEvent (deferral/disappearance/cross-body).
- Knowledgebase context scoped to topic canonical name + aliases.

### JSON schema (draft)
{
  "topics": [
    {
      "topic_id": 123,
      "topic_name": "Canonical topic name",
      "lifecycle_status": "active|dormant|resolved|recurring",
      "factual_record": [
        { "statement": "...", "citations": ["Packet Page 12", "Minutes Page 4"] }
      ],
      "institutional_framing": [
        { "statement": "...", "source": "staff_summary|agenda_title|minutes_language", "citations": ["Packet Page 5"] }
      ],
      "civic_sentiment": [
        { "observation": "...", "evidence": "public_comment|recurrence", "citations": ["Minutes Page 7"] }
      ],
      "continuity_signals": [
        { "signal": "recurrence|deferral|disappearance|cross_body_progression", "details": "...", "citations": ["Agenda Item 3"] }
      ],
      "decision_hinges": ["..."],
      "ambiguities": ["..."],
      "verification_notes": ["..."]
    }
  ],
  "meeting_level": {
    "tldr": ["..."],
    "verification_notes": ["..."]
  }
}

Notes:
- All factual_record entries must include citations or be omitted.
- Civic sentiment entries must use observational language and avoid unanimity claims.
- If citations are not available, state "Not specified" rather than infer.
- Community signals (e.g., admin-reported, social media, neighborhood reports) must be labeled as
  "Resident-reported (no official record)" and stored separately from factual record.

## Proposed Implementation Plan

### 1) Context builder (new service)
- Add Topics::SummaryContextBuilder to assemble per-topic context:
  - Agenda item text (title, summary, recommended_action).
  - Minutes excerpts tied to agenda items when available.
  - Packet extraction pages linked to agenda items.
  - Topic lifecycle and status event signals.
  - Knowledgebase context scoped by topic canonical_name + aliases.
- Output a deterministic, auditable context payload per topic.

### 2) OpenAI prompt updates (Ai::OpenAiService)
- Add new methods:
  - analyze_topic_summary(context_json)
  - render_topic_summary(plan_json)
- Enforce explicit separation: factual record / institutional framing / civic sentiment.
- Require citations for factual record and framing claims.
- Include a consistency check: if citations missing, mark "Not specified".

### 3) Job orchestration (SummarizeMeetingJob)
- When meeting summaries run:
  - Build topic-aware context for all approved topics linked to the meeting.
  - Generate topic-aware summary output in addition to existing meeting-level recap.
  - Store output in a new summary type or a new model (see Open Decisions).

### 4) Storage strategy (decision: new model)
- Introduce TopicSummary model keyed by topic_id + meeting_id.
- Keep MeetingSummary for meeting-level recaps only.
- Migration required; proceed only after confirming schema change (confirmed).

### 5) Retrieval updates (topic-aware)
- Extend RetrievalService to accept topic-specific query text that includes:
  - topic canonical_name + aliases
  - recent appearances (meeting dates, body_name)
  - short list of recent agenda item titles
- Cap context size per topic; preserve verified/unverified labels.

### 6) UI rendering (follow-on to Issue 39)
- Render topic-aware summary sections on meeting pages with clear labels:
  - Factual Record
  - Institutional Framing
  - Civic Sentiment (observational)
- Show citations inline.

## Tests (Minitest)
- Context builder tests:
  - Ensures topic-specific agenda items are included and unrelated items are excluded.
  - Ensures continuity signals surface when TopicStatusEvent exists.
- Prompt output contract test:
  - JSON keys present; missing citations do not appear in factual_record.
- Job idempotency test:
  - Re-running SummarizeMeetingJob updates existing summaries without duplicates.

## Open Decisions (confirm before implementation)
1) Whether to deprecate meeting-level recaps once topic-aware summaries are stable.

## Decisions Made
1) Storage: use TopicSummary model keyed by topic_id + meeting_id.
2) Citations: store structured citations with document identifiers; render friendly labels (e.g., "Packet Page 12") in UI.

## Implementation Progress (2026-02-15)
- [x] TopicSummary model + migration (topic_id, meeting_id, content, generation_data).
- [x] Topics::SummaryContextBuilder implemented (metadata, agenda items, continuity signals).
- [x] Ai::OpenAiService updated with analyze_topic_summary and render_topic_summary.
- [x] SummarizeMeetingJob updated to generate topic summaries for approved topics.
- [x] Tests added for ContextBuilder and Job logic.
- [x] Topic-aware retrieval query builder and context caps.
- [x] Citation validation for factual record and institutional framing.
- [x] Topic summaries rendered on meeting page with AI labeling.
- [x] Meeting recap labeled as a projection (topic summaries are primary lens).
- [x] Resident-reported context field + admin UI + labeled display.
- [x] Follow-up issue created for resident submissions intake (#52).

## Remaining Work (UI Rendering)
Status: Completed for Issue #49.

## Remaining Work (Compliance Gaps)
Status: Completed for Issue #49.

## Detailed Plan to Close Gaps
### Phase 0: External context design (resident-reported)
1) Define a dedicated data structure for external context:
   - Separate from factual_record and institutional_framing.
   - Stored with provenance fields: source_type, source_notes, added_by, added_at.
2) Decide where external context lives:
   - Option A: TopicSummary.generation_data["external_context"] (preferred for now).
   - Option B: new TopicContextSource model (future work).
3) Add labeling rules:
   - Always render with the label "Resident-reported (no official record)".
   - Never allow external context to appear in factual_record.
4) UI placement:
   - Display external context in Topic summary panels under its own heading.
   - Keep it visually distinct (badge + short disclaimer).
### Phase A: Citations + evidence
1) Extend SummaryContextBuilder to collect page-aware citations:
   - Use `extractions` on MeetingDocument for packet pages (page_number + cleaned_text).
   - Link agenda item to its attached documents (`agenda_item_documents`).
   - Include citation metadata in `attachments` and a top-level `citations` array.
2) Update OpenAiService topic prompts to require citation object references:
   - Enforce that factual_record includes citation references, not raw strings.
3) Validate output before storage:
- Strip any factual_record entries missing citations.
- Preserve ambiguities and verification_notes when citations are missing.
- Allow explicitly labeled resident-reported entries only in a separate section.

### Phase B: Retrieval, continuity, and query shaping
1) Add topic-aware query builder utility:
   - Use canonical name + aliases; include latest 3 appearances and top agenda items.
   - Pass a capped query to RetrievalService (e.g., limit 5).
2) Add continuity citation mapping:
   - Attach agenda item ids and meeting ids in `continuity_signals`.

### Phase C: UI + labeling
1) Add Topic Summaries section on Meeting Show:
- Render Markdown; show section labels.
- Include a visible "AI-generated" label and citation footnotes.
2) Ensure official documents are linked next to summaries.
3) Defer meeting-level summary deprecation until topic summaries are stable.
4) Display external context with label: "Resident-reported (no official record)".

## Decisions (External Context)
1) External context is attached to a Topic (not meeting-specific by default).
2) Admins manage external context via existing admin topic UI.
3) Add a new dedicated field for resident-reported context (do not reuse topic description).
4) Resident submissions are out of scope for now; consider a future issue for admin review intake.
