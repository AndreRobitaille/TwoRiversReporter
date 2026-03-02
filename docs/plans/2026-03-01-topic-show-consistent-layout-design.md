# Topic Show Page: Consistent Layout + Structured Rendering

**Date:** 2026-03-01
**Issue:** #33 — Topic pages: empty/error/low-signal states

## Problem

Topic show pages currently hide sections when empty, so pages look different
depending on data availability. Residents see a full page for one topic and a
sparse one for another with no explanation. Additionally, AI-generated editorial
and record content renders as text blocks parsed from markdown — a lossy
round-trip from the structured JSON that pass 1 already produces.

## Design

### Principle: Inverted Pyramid

Every topic page shows all sections in a fixed order, most important first.
A resident who closes the page after 3 seconds still gets the headline and
what-to-watch. Empty sections show contextual messages instead of hiding.

### Section Order

| # | Section | Data Source | Visual Treatment |
|---|---------|-------------|-----------------|
| 1 | Header | `topic.name`, `.description`, `.lifecycle_status`, `.resident_impact_score` | h1 + subtitle + badges. Always present. |
| 2 | What to Watch | `generation_data.editorial_analysis.what_to_watch` | Warm callout card. Stands out visually. |
| 3 | Coming Up | `@upcoming` (TopicAppearance → Meeting) | Meeting cards in grid (existing style). |
| 4 | The Story | `generation_data.editorial_analysis.current_state` + `process_concerns` as secondary callout | Prose card + optional concern callout. |
| 5 | Key Decisions | `@decisions` (Motion + Votes) | Existing vote breakdown cards. |
| 6 | Record | `generation_data.factual_record` (array of `{date, event, meeting}`) | Timeline layout: date left, event right, meeting as metadata. |

### Empty State Messages

| Section | Message |
|---------|---------|
| What to Watch | "No analysis available yet for this topic." |
| Coming Up | "No upcoming meetings scheduled for this topic." |
| The Story | "This topic is being tracked but hasn't been fully analyzed yet. Check back after the next meeting." |
| Key Decisions | "No votes or motions recorded for this topic." |
| Record | "No meeting activity recorded for this topic yet." |

### Structured JSON Rendering

**Current flow:** Pass 1 → structured JSON → Pass 2 → markdown → helper parses
markdown → HTML.

**New flow:** Pass 1 → structured JSON → ERB renders HTML directly from
`generation_data`.

Pass 2 markdown fields (`editorial_content`, `record_content`) become fallbacks
for:
- `headline_only` tier briefings (9 exist, no `generation_data`)
- Any future edge case where `generation_data` is missing

The view checks `generation_data` first, falls back to markdown fields.

### `generation_data` Schema (Confirmed Consistent)

All 54 full-tier briefings have this structure:

```json
{
  "headline": "string",
  "upcoming_headline": "string|null",
  "editorial_analysis": {
    "current_state": "string (1-3 sentences)",
    "what_to_watch": "string (1-2 sentences)",
    "process_concerns": ["string"],
    "pattern_observations": ["string"]
  },
  "factual_record": [
    { "date": "YYYY-MM-DD", "event": "string", "meeting": "string" }
  ],
  "resident_impact": { "score": 1-5, "rationale": "string" },
  "ambiguities": ["string"],
  "civic_sentiment": ["string"],
  "continuity_signals": [{ "signal": "string", "details": "string", "meeting": "string" }],
  "verification_notes": ["string"]
}
```

### Timeline Layout (Record Section)

```
  Sep 2    Council agenda included update on construction,
  2025     marketing, and lot sales.
    │                                     City Council
    │
  Nov 5    Sandy Bay topic appeared on the agenda.
  2025                            Public Works Committee
    │
  Feb 24   Phase 3 Contract 6-2025 Update; no vote
  2026     reported yet.
                                  Public Works Committee
```

CSS: vertical line connecting entries, date column fixed-width left, event text
right, meeting name as muted metadata below event.

### What Does NOT Change

- Pass 1 and Pass 2 AI pipeline stays as-is (pass 2 still runs, results stored)
- `TopicBriefing` model and schema unchanged
- `TopicSummary` (per-meeting) rendering unchanged
- Topic cards, homepage headline cards unchanged
- Topics index page unchanged
- Key Decisions rendering style unchanged (just always-visible now)

### Files to Modify

- `app/views/topics/show.html.erb` — Rewrite with fixed section order + empty states
- `app/helpers/topics_helper.rb` — Add helpers for timeline rendering, generation_data extraction
- `app/assets/stylesheets/application.css` — Timeline styles, what-to-watch callout, empty state tweaks
- `app/controllers/topics_controller.rb` — May need to expose `generation_data` (already available via `@briefing`)

### Files NOT Modified

- AI prompts / OpenAI service
- TopicBriefing model
- Pass 1 or Pass 2 generation logic
- Any other views
