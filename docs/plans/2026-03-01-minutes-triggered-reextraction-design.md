# Minutes-Triggered Topic Re-Extraction

**Date:** 2026-03-01

## Problem

`ExtractTopicsJob` runs once — when agenda HTML is first parsed by
`ParseAgendaJob`. It never re-runs when the authoritative minutes PDF
arrives weeks or months later. This means:

- Meetings where initial extraction failed get zero topic associations
  permanently (e.g., meetings 131 and 52 have 25+ agenda items but no
  topics).
- Agenda-only context produces sparse or incomplete topic associations
  because agenda titles are often generic ("PUBLIC HEARING", "ACTION
  ITEMS").
- The richest document type — minutes — is never used for topic
  extraction despite containing discussion details, public comment
  records, motion descriptions, and vote outcomes.

Most meetings (subcommittees, boards, commissions) only ever publish
an agenda PDF and later a minutes PDF. No packet. Minutes are the
first and only source of substantive content for these meetings.

## Document Lifecycle Context

| Stage | Who gets it | Content quality | Used for extraction today? |
|-------|------------|-----------------|---------------------------|
| Agenda HTML | All meetings | Sparse — item titles, sometimes summaries | Yes (triggers ExtractTopicsJob) |
| Packet PDF | Council + a few others | Rich but noisy — supporting docs mixed with consent agenda attachments | Partially (8K chars as supplementary context) |
| Minutes PDF | All meetings (weeks/months later) | Authoritative factual record — discussion, motions, votes, attendance | No — only used for summarization, vote extraction, membership extraction |

## Design

### 1. Trigger re-extraction when minutes arrive

In `Documents::AnalyzePdfJob`, add `ExtractTopicsJob.perform_later`
when processing `minutes_pdf` documents. This mirrors the existing
triggers for `SummarizeMeetingJob`, `ExtractVotesJob`, and
`ExtractCommitteeMembersJob`.

```ruby
# In AnalyzePdfJob, after line 88 (existing summarization trigger):
if document.document_type == "minutes_pdf"
  ExtractVotesJob.perform_later(document.meeting_id)
  ExtractCommitteeMembersJob.perform_later(document.meeting_id)
  ExtractTopicsJob.perform_later(document.meeting_id)  # NEW
end
```

### 2. Prioritize minutes over packet in document context

Modify `ExtractTopicsJob#build_meeting_document_context` to prefer
minutes text when available, skipping packet text. Minutes are
authoritative and clean (no embedded committee minutes contamination).
Packets are valuable for supporting detail but create noise when used
as bulk AI context.

**Current behavior:** Includes all `packet_pdf` and `minutes_pdf`
documents, each truncated to 8,000 chars.

**New behavior:**

```
if minutes_pdf exists with text:
  use minutes text (up to 25,000 chars)
  skip packet text
else if packet_pdf exists with text:
  use packet text (8,000 chars, current behavior)
end
```

**Rationale for 25K limit:** Minutes range from 1.2K (Architectural
Control) to 23K (City Council). 25K covers all meetings. Most
subcommittee minutes are under 5K.

**Rationale for skipping packet when minutes exist:** Packet text for
council meetings includes consent agenda content (embedded committee
minutes, financial reports, check registers) that contaminates topic
extraction. When minutes exist, they provide the same factual
information about what was discussed without the noise.

### 3. ExtractTopicsJob remains additive (no clearing)

The job already uses `AgendaItemTopic.find_or_create_by!`, so
re-running with richer context adds new associations without
duplicating existing ones. The `after_create` callback on
`AgendaItemTopic` is guarded with `unless TopicAppearance.exists?`,
preventing duplicate appearances.

Wrong associations from the initial sparse-context run will persist,
but investigation shows these are rare — the agenda structure
provides good structural anchors even with sparse titles.

### Epistemic Note

Minutes are the city clerk's account of the meeting — strong for
**Factual Record** (votes, motions, attendance, what was discussed)
but **Institutional Framing** for discussion characterizations and
public comment summaries.

For topic *extraction* (classifying agenda items into topics), this
distinction is immaterial — we are identifying factual associations
("what topics were discussed at this meeting"), not generating
interpretive prose.

For topic and meeting *summarization* (already re-triggered by
`SummarizeMeetingJob` when minutes arrive), the epistemic distinction
is handled by the existing editorial voice constraints and
TOPIC_GOVERNANCE.md guidelines.

Future work: when both packet and minutes exist for council meetings,
summaries should ideally triangulate — using packet supporting docs
for substance and minutes for factual record, treating both through
the three-category epistemic lens. That is a separate design.

## What Does NOT Change

- `ExtractTopicsJob` core logic — same AI prompt, same
  agenda-item-anchored approach, same `DEFAULT_MODEL` (gpt-5.2)
- Existing `AgendaItemTopic` / `TopicAppearance` records (additive)
- `SummarizeMeetingJob` (already re-runs on minutes, already replaces
  packet analysis with minutes recap)
- `ExtractVotesJob` and `ExtractCommitteeMembersJob` (already
  triggered by minutes)
- AI prompts (minutes content flows through existing
  `meeting_documents_context` parameter)
- `ParseAgendaJob` (still triggers initial extraction from agenda)

## Files to Modify

- `app/jobs/documents/analyze_pdf_job.rb` — Add
  `ExtractTopicsJob.perform_later` trigger for minutes
- `app/jobs/extract_topics_job.rb` —
  `build_meeting_document_context` to prefer minutes over packet

## Cost Impact

**Negligible to net-negative.** Re-extraction uses gpt-5.2 (same as
initial extraction). For most subcommittee meetings, minutes are
under 5K chars — similar to current agenda-only context. For council
meetings, using minutes (8-23K) instead of packet (truncated to 8K)
may slightly increase input tokens but eliminates the noisy packet
content. One additional API call per meeting when minutes arrive.

## Verification

After implementation:
1. Re-run `ExtractTopicsJob` for meeting 131 (Feb 2 council, zero
   topics) — should produce topic associations from minutes
2. Re-run for meeting 52 (Oct 20 council, zero topics) — same
3. Compare topic associations before/after for a meeting that already
   has associations (e.g., meeting 44, Jan 19 council) — should add
   new associations without losing existing ones
4. Check that subcommittee meetings (Plan Commission, Public Works,
   Committee on Aging) get richer associations from minutes
