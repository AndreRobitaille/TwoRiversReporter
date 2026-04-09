# Auto Knowledge Extraction Design

**Date:** 2026-04-09
**Status:** Draft
**Scope:** Automated population of the knowledgebase from meeting content, with cross-meeting pattern detection and auto-triage.

## Problem

The knowledgebase infrastructure (KnowledgeSource, KnowledgeChunk, RetrievalService, prompt injection) is fully built and wired into four AI prompt points (meeting summaries, topic summaries, topic briefings, triage). But it's empty. No content has ever been populated, so all retrieval calls return nothing.

The knowledgebase should contain **institutional memory** — durable civic facts that live between the lines of official documents. Things like who owns businesses, who is married or business partners, resident sentiment signals from public comment patterns, and historical context that would otherwise be lost. A longtime city hall reporter would know these things; a newcomer reading any single document wouldn't.

## Design Principles

1. **Don't touch the existing pipeline.** Extraction runs downstream of summarization, never inside it. Zero risk to working production code.
2. **Confidence over coverage.** Missing a fact is fine. Creating a wrong fact that silently poisons future summaries is not. The system should err heavily toward not creating entries.
3. **No context compounding.** AI-generated knowledge must not amplify its own speculation through feedback loops. Strict guardrails prevent self-referential amplification.
4. **Mostly self-managing.** Auto-triage handles the vast majority of entries. Admin intervention is rare correction, not routine review.
5. **Knowledge entries are never public.** They exist only as context injected into AI prompts. Residents never see them directly.

## Schema Changes

### KnowledgeSource — new fields

| Field | Type | Purpose |
|-------|------|---------|
| `origin` | string | `"manual"` (admin-created), `"extracted"` (per-meeting AI), `"pattern"` (cross-meeting AI). Default: `"manual"`. |
| `reasoning` | text | AI's explanation of why this fact was extracted. "Here's why I think that." Required for extracted/pattern entries. |
| `confidence` | float | AI's self-assessed confidence (0.0–1.0). Only entries >= 0.7 are created. Stored for retroactive threshold tuning. |
| `status` | string | `"proposed"`, `"approved"`, `"blocked"`. Replaces the existing unused `status` field. Default: `"proposed"` for extracted/pattern, `"approved"` for manual. |

The existing `active` boolean remains and controls retrieval eligibility independently of status. An entry must be both `status: "approved"` AND `active: true` to be returned by RetrievalService.

### No new tables

`KnowledgeSourceTopic` already handles topic linking. No new join tables or models needed.

## Per-Meeting Knowledge Extraction

### Job: `ExtractKnowledgeJob`

**Trigger:** Enqueued by `SummarizeMeetingJob` after summarization completes. Same pattern as other downstream jobs.

**Inputs:**
- `MeetingSummary.generation_data` — structured JSON (headline, highlights, public_input, item_details). Acts as a map of what was important.
- `MeetingDocument.extracted_text` — raw minutes/transcript text, capped at 25K chars. Provides the deeper detail the summary trimmed.
- Existing relevant knowledge entries — retrieved via `RetrievalService` using the meeting's topics as query scope. Shown to the AI so it doesn't duplicate what's already known.

**Prompt:** Uses `PromptTemplate` named `extract_knowledge`. The prompt provides:
1. The meeting summary (what mattered)
2. The raw document text (the details)
3. Existing knowledge entries (what we already know)
4. Instructions emphasizing:
   - Extract durable civic facts only — things that will still be true and useful months from now
   - One fact per entry, with title, body, reasoning, and confidence score
   - New entries must be grounded in the meeting content provided, not in existing knowledge entries
   - Existing knowledge entries are shown to avoid duplication only — they are not evidence for new entries
   - Returning an empty array is the correct answer most of the time
   - Normal civic process (committee referrals, multi-reading ordinances, tabling for information) is not noteworthy

**Response format:** JSON array of objects:
```json
[
  {
    "title": "John Smith owns Smith's Marina",
    "body": "John Smith disclosed ownership of Smith's Marina on Washington Street during recusal from marina-related agenda items.",
    "reasoning": "Smith stated 'I need to recuse myself as owner of Smith's Marina' during agenda item 7 discussion of marina dock permits.",
    "confidence": 0.92,
    "topic_names": ["Marina Dock Permits"]
  }
]
```

**Processing:**
1. Parse JSON response
2. Filter entries below confidence threshold (0.7)
3. For each qualifying entry:
   - Create `KnowledgeSource` with `origin: "extracted"`, `source_type: "note"`, `status: "proposed"`, `active: true`
   - Store title, body, reasoning, confidence
   - Link to existing approved topics via `KnowledgeSourceTopic` by matching `topic_names` from the response against `Topic.approved`. No new topics are created — if a topic name doesn't match an existing approved topic, that link is silently skipped.
4. Enqueue `AutoTriageKnowledgeJob` with 3-minute delay (batch all proposed entries from this meeting)

**Idempotency:** The job reads existing KB entries as context, so re-running should not produce duplicates. As additional safety, the reasoning field naturally references the specific meeting content, making duplicates detectable.

## Cross-Meeting Pattern Extraction

### Job: `ExtractKnowledgePatternsJob`

**Schedule:** Weekly, Monday 3am (alongside existing `RefreshTopicDescriptionsJob` in `config/recurring.yml`). Also triggerable manually via admin or rake task.

**Inputs:**
- All approved `origin: "extracted"` knowledge entries (first-order facts from individual meetings)
- All approved `origin: "manual"` knowledge entries (admin corrections/additions)
- Recent topic briefing `generation_data` (last 90 days)
- Topic metadata: appearance counts, lifecycle status, committees involved

**Critically: does NOT read `origin: "pattern"` entries.** Patterns are always derived from first-order facts, never from other patterns. This prevents compounding.

**Prompt:** Uses `PromptTemplate` named `extract_knowledge_patterns`. Looks for:
- **Behavioral patterns** — recurring recusals, consistent voting blocs, members who always speak on certain topics
- **Escalation signals** — topics where public comment volume is increasing across meetings, same residents returning repeatedly
- **Relationship inference** — shared business interests, disclosed conflicts of interest appearing across multiple meetings
- **Institutional stalling** — items that keep getting tabled without progress (distinct from normal multi-reading process)

**Explicit prompt guidance on normal process:**
- Committee referrals between bodies are standard procedure, not noteworthy
- Multi-reading ordinance processes are required by law, not stalling
- Tabling for more information is responsible governance, not avoidance
- Consent agenda bundling is efficiency, not hiding items
- Focus on things that would surprise or inform a resident, not things that are just how municipal government works

**Response format:** Same JSON structure as per-meeting extraction, with `confidence` scores.

**Processing:** Same as per-meeting — create proposed entries with `origin: "pattern"`, enqueue `AutoTriageKnowledgeJob`.

## Auto-Triage

### Job: `AutoTriageKnowledgeJob`

**Trigger:** Enqueued 3 minutes after extraction jobs create proposed entries. Same delay pattern as topic auto-triage.

**Inputs:** All `KnowledgeSource` entries with `status: "proposed"`.

**Prompt:** Uses `PromptTemplate` named `triage_knowledge`. For each entry, evaluates:
- **Grounded?** Does the reasoning cite specific meeting content, or is it vague/speculative?
- **Durable?** Will this fact still be useful months from now, or is it ephemeral?
- **Not duplicative?** Is this genuinely new information, not restating something already in the KB?
- **Not normal process?** Is this a misread of standard civic procedure as noteworthy?
- **Appropriate confidence?** Does the claimed confidence match the strength of the evidence?

**Decisions:** `approve` or `block` each entry. No "needs review" middle state — the AI makes a call. If it's uncertain, it blocks. Admin can always unblock later.

**Processing:** Updates `status` on each entry. Approved entries become available for retrieval immediately.

## Anti-Compounding Guardrails

The central risk is a feedback loop: extraction creates a slightly wrong entry → future summaries read it as context → summaries frame things differently → next extraction builds on the shifted framing → compounds further.

### Guardrail 1: Source-type labeling in prompts

When `RetrievalService` formats knowledge entries for injection into summarization prompts, the label reflects origin:

| Origin | Label in prompt | AI instruction |
|--------|----------------|----------------|
| `manual` | `[ADMIN NOTE]` | Treat as authoritative background context |
| `extracted` | `[DOCUMENT-DERIVED]` | Background context derived from meeting documents — reference as "based on meeting records" not as established fact |
| `pattern` | `[PATTERN-DERIVED]` | System-identified pattern across meetings — treat as "the system has noticed..." not as confirmed fact |

Summarization prompts are updated to include handling instructions for each label type.

### Guardrail 2: Grounding requirement

The extraction prompt requires that every entry's `reasoning` field cite specific text from the meeting content. Entries with vague reasoning ("it seems like..." / "based on context...") should not be created. The triage prompt checks for this.

### Guardrail 3: No self-referential amplification

The extraction prompt explicitly states: "Existing knowledge entries are shown so you don't duplicate them. Do not treat them as evidence for new entries. New entries must be grounded in the meeting content provided, not in existing knowledge entries."

### Guardrail 4: Pattern entries don't compound on patterns

`ExtractKnowledgePatternsJob` only reads `origin: "extracted"` and `origin: "manual"` entries. It never reads `origin: "pattern"` entries. Patterns are always one derivation step from source documents.

### Guardrail 5: Hard cap on KB context in prompts

The existing `max_chars: 6000` limit on topic retrieval and the `retrieve_context` limits remain unchanged. KB context is always a minority of any prompt. Meeting content dominates.

## Prompt Template Changes

### New templates (3)

| Template name | Purpose |
|---------------|---------|
| `extract_knowledge` | Per-meeting knowledge extraction from summaries + raw text |
| `extract_knowledge_patterns` | Cross-meeting pattern detection from accumulated facts |
| `triage_knowledge` | Auto-approve/block proposed knowledge entries |

All follow existing conventions: `system_role` + `instructions` with `{{placeholder}}` interpolation, versioned via `PromptVersion` on save, editable in admin UI.

### Modified templates

Existing summarization templates (`analyze_meeting_content`, `analyze_topic_summary`, `analyze_topic_briefing`) need updated context handling instructions that explain the three trust labels (`ADMIN NOTE`, `DOCUMENT-DERIVED`, `PATTERN-DERIVED`) and how to treat each.

## RetrievalService Changes

### Retrieval filtering

`retrieve_context` and `retrieve_topic_context` must filter to `status: "approved"` AND `active: true`. Currently only filters on `active`.

### Format changes

`format_context` and `format_topic_context` replace the VERIFIED/UNVERIFIED labeling with origin-based labels:
- `origin: "manual"` → `[ADMIN NOTE: {title}]`
- `origin: "extracted"` → `[DOCUMENT-DERIVED: {title}]`
- `origin: "pattern"` → `[PATTERN-DERIVED: {title}]`

## Admin UI Changes

### Knowledge sources index

- Add status filter tabs: All / Proposed / Approved / Blocked (same pattern as topics admin)
- Add origin filter: All / Document-Derived / Pattern-Derived / Admin Notes
- Show reasoning field in list view (truncated)

### Knowledge source show/edit

- Display `reasoning` prominently for extracted/pattern entries
- Display `confidence` score
- Display `origin` as a badge
- Editing an extracted/pattern entry changes `origin` to `"manual"`, elevating its trust level

### Meeting admin (optional enhancement)

- Small section on meeting show: "Knowledge extracted from this meeting" listing entries whose reasoning references this meeting. Useful for spot-checking.

## Pipeline Integration

```
Existing pipeline (unchanged):
  Scraper → Documents → Topics → Summarization

New downstream addition:
  SummarizeMeetingJob completes
    → enqueues ExtractKnowledgeJob
      → reads: generation_data + raw text + existing KB
      → creates proposed KnowledgeSource entries (origin: "extracted")
      → enqueues AutoTriageKnowledgeJob (3 min delay)
        → approves/blocks entries
        → approved entries available for retrieval in future prompts

Weekly schedule (Monday 3am):
  ExtractKnowledgePatternsJob
    → reads: approved extracted + manual entries, recent summaries
    → creates proposed KnowledgeSource entries (origin: "pattern")
    → enqueues AutoTriageKnowledgeJob (3 min delay)
      → approves/blocks entries
```

## Recurring Jobs Addition

| Job | Schedule | Purpose |
|-----|----------|---------|
| `extract_knowledge_patterns` | Mondays at 3:30am | Cross-meeting pattern detection (runs after description refresh) |

## Model Constants

- `CONFIDENCE_THRESHOLD = 0.7` — minimum confidence for entry creation (on `ExtractKnowledgeJob`)
- `ORIGINS = %w[manual extracted pattern]` — valid origin values (on `KnowledgeSource`)
- `STATUSES = %w[proposed approved blocked]` — valid status values (on `KnowledgeSource`)
- `RAW_TEXT_LIMIT = 25_000` — character cap on raw document text sent to extraction prompt

## What This Does NOT Include

- **Public-facing knowledge display.** Knowledge entries are never shown to residents. They exist only as AI prompt context.
- **Embedding changes.** The existing chunking/embedding pipeline (IngestKnowledgeSourceJob) works for extracted entries — they're short text notes that get chunked and embedded like any other KnowledgeSource.
- **pgvector migration.** The pure-Ruby vector search remains. Scalability improvements are a separate concern.
- **Knowledge entry expiration/decay.** Entries persist until blocked or deleted. If staleness becomes a problem, add a refresh mechanism later.
- **Category/tag system for entries.** Topic linking via KnowledgeSourceTopic is sufficient. Additional categorization deferred until patterns emerge.
