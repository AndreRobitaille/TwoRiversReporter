# Topic Briefing Architecture — Design Document

**Issue**: #64 (Topic summary architecture — cost efficiency and freshness)
**Date**: 2026-02-21

---

## Problem

The current `TopicSummary` model generates one summary per topic per meeting
during `SummarizeMeetingJob`. Only the most recent is displayed. This wastes
LLM spend, shows a narrow single-meeting snapshot instead of the full topic
arc, and gives residents no narrative context about how a topic evolved.

Residents follow topics, not meetings. When they check in after a few weeks
they need the full story — not a snapshot of meeting #8 out of 8.

## Design Decisions

### Editorial Voice

Summaries shift from neutral institutional reporting to resident-facing
editorial analysis:

- **Skeptical of process and decisions, not of people.** Question what's
  being done and why. Don't name-and-shame or ascribe bad intent.
- **Editorialize early.** Residents who check in casually can't connect
  the dots themselves — the summary does that work for them.
- **"Means to an end" framing is fair game.** Pointing out that a decision
  benefits X at the expense of Y is fine. Saying someone is corrupt is not.
- **Respect community reputation dynamics.** In a tight social-capital
  community, anything that reads as airing dirty laundry will turn people
  off the whole site.

This voice applies to both per-meeting `TopicSummary` rendering and the
rolling `TopicBriefing`.

### Data Model

**New model: `TopicBriefing`** — one record per topic, updated in place.

| Column | Type | Purpose |
|--------|------|---------|
| `topic_id` | integer, unique | One briefing per topic |
| `headline` | string | TL;DR line at top of topic page |
| `editorial_content` | text | "What's Going On" section (markdown) |
| `record_content` | text | "Record" section (cited bullet list, markdown) |
| `generation_data` | jsonb | Full structured AI analysis for audit |
| `generation_tier` | string | `headline_only`, `interim`, `full` |
| `last_full_generation_at` | datetime | When the full narrative was last regenerated |
| `triggering_meeting_id` | integer, FK | Which meeting triggered the last generation |

**Existing model: `TopicSummary`** — unchanged schema. Per-meeting records
are kept as structured building blocks for the briefing. Rendering prompt
updated to new editorial voice.

### Three-Tier Generation Pipeline

Generation is event-driven, not scheduled. Cost scales with meeting
frequency, not a clock.

#### Tier 1: Meeting Scheduled (no AI cost)

```
AgendaItemTopic created for future meeting
  → UpdateTopicBriefingJob (tier: :headline_only)
  → Derives headline from data: "Coming up at Council, Mar 4"
  → Sets generation_tier = "headline_only"
```

Hooks into existing `AgendaItemTopic after_create` callback chain.

#### Tier 2: Agenda/Packet Added (1 cheap AI call)

```
Document extraction completes, meeting has no minutes yet
  → UpdateTopicBriefingJob (tier: :interim)
  → 1x gpt-5-mini call: update headline + generate upcoming note
  → Appends note to editorial_content
  → Sets generation_tier = "interim"
```

#### Tier 3: Minutes Published (2 reasoning calls — full regen)

```
SummarizeMeetingJob completes for meeting with minutes
  → Per-meeting TopicSummary generated (as today, new voice)
  → GenerateTopicBriefingJob (tier: :full)
  → Assemble hybrid context:
    - All prior TopicSummary.generation_data (oldest first)
    - Raw docs from last 2-3 meetings
    - KB context via RetrievalService
    - Topic metadata (lifecycle, aliases, appearances)
  → 1x gpt-5.2: structured analysis → generation_data JSON
  → 1x gpt-5.2: render editorial_content + record_content + headline
  → Sets generation_tier = "full", last_full_generation_at = now
```

### Job Structure

| Job | Tier | Model | Trigger |
|-----|------|-------|---------|
| `UpdateTopicBriefingJob` | headline_only | none | `AgendaItemTopic` created for future meeting |
| `UpdateTopicBriefingJob` | interim | gpt-5-mini | Document extraction completes, no minutes yet |
| `GenerateTopicBriefingJob` | full | gpt-5.2 | `SummarizeMeetingJob` completes for meeting with minutes |

### Prompt Design

#### Full Generation — Pass 1: Structured Analysis

Model: gpt-5.2, `response_format: { type: "json_object" }`

Input:
- Topic metadata (name, lifecycle, aliases, first/last seen)
- Array of prior `TopicSummary.generation_data` ordered by meeting date
- Raw docs from last 2-3 meetings (agenda items, extractions, citations)
- KB context chunks

Output JSON:
```json
{
  "headline": "One-sentence TL;DR of current status",
  "editorial_analysis": {
    "current_state": "What just happened / where things stand",
    "pattern_observations": ["Deferred twice before vote", "..."],
    "process_concerns": ["Safety framing used to justify...", "..."],
    "what_to_watch": "Forward-looking note if applicable"
  },
  "factual_record": [
    {"event": "...", "date": "...", "citations": ["..."]}
  ],
  "civic_sentiment": [
    {"observation": "...", "evidence": "...", "citations": ["..."]}
  ],
  "continuity_signals": [
    {"signal": "recurrence|deferral|disappearance|...", "details": "...", "citations": ["..."]}
  ],
  "resident_impact": {"score": 1, "rationale": "..."},
  "ambiguities": ["..."],
  "verification_notes": ["..."]
}
```

Key differences from current `analyze_topic_summary`:
- `editorial_analysis` replaces `institutional_framing` — AI analyzes
  process, not just describes framing
- `pattern_observations` and `process_concerns` give explicit places to
  editorialize
- `what_to_watch` provides forward-looking context
- `factual_record` spans all meetings, not just one

#### Full Generation — Pass 2: Markdown Rendering

Model: gpt-5.2. Takes Pass 1 JSON and renders:

- **`headline`**: Pulled from Pass 1 JSON (no extra call)
- **`editorial_content`**: Prose "What's Going On." Editorial voice,
  resident-facing, skeptical of process. Weaves in pattern observations,
  process concerns, civic sentiment. Inline citations.
- **`record_content`**: Bullet list "Record." Chronological, cited,
  factual. Every claim has a document reference.

#### Interim Generation (Tier 2)

One gpt-5-mini call:

Input:
- Topic name + current headline
- New agenda item titles and document excerpts
- Current editorial_content (to append to, not replace)

Output:
- Updated headline
- Brief upcoming note to append to editorial_content

### Topic Show Page Layout

```
┌─────────────────────────────────┐
│ ← Back to Topics                │
│                                 │
│ Downtown Parking Changes        │  h1: topic name
│ Ongoing downtown parking debate │  topic.description
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Council approved modified   │ │  HEADLINE
│ │ parking plan 4-3 on Feb 18  │ │  card--warm, bold, lg font
│ │                    ○ Updated│ │  badge if recent
│ └─────────────────────────────┘ │
│                                 │
│ Coming Up                       │  (if future meeting exists)
│ ┌──────────┐ ┌──────────┐      │  existing cards
│ │ Council  │ │ Zoning   │      │
│ │ Mar 4    │ │ Mar 11   │      │
│ └──────────┘ └──────────┘      │
│                                 │
│ What's Going On                 │  EDITORIAL
│ ┌─────────────────────────────┐ │  white card, prose style
│ │ The city just approved...   │ │  relaxed line-height
│ │ Staff pitched this as a     │ │  inline citations
│ │ safety fix, but residents   │ │
│ │ have been pushing back...   │ │
│ │                             │ │
│ │ Worth watching: this        │ │
│ │ follows a pattern...        │ │
│ └─────────────────────────────┘ │
│                                 │
│ Record                          │  FACTUAL
│ ┌─────────────────────────────┐ │  surface-raised bg
│ │ • Oct 15 — Original        │ │  chronological bullets
│ │   proposal [Packet p.3]    │ │  citations in secondary
│ │ • Nov 19 — Deferred        │ │  color
│ │ • Jan 21 — Deferred again  │ │
│ │ • Feb 18 — Approved 4-3    │ │
│ │   [Minutes p.7]            │ │
│ └─────────────────────────────┘ │
│                                 │
│ Key Decisions                   │  existing section
│ ...                             │
│                                 │
│ ← Back to Topics                │
└─────────────────────────────────┘
```

#### Progressive Fill-In

| Tier | What's visible |
|------|---------------|
| `headline_only` | Headline card only |
| `interim` | Headline + editorial (with upcoming note) |
| `full` | Headline + editorial + record |

No placeholders — sections that don't exist yet simply aren't rendered.

#### Visual Details

- **Headline card**: `card--warm` (golden-brown accent, `#fffbf5` bg).
  Bold, `font-lg`. "New"/"Updated" badge if briefing changed within 7 days.
- **Editorial card**: Standard white card. `font-base`,
  `line-height: 1.625` for readable prose. Inline citation links.
- **Record card**: `surface-raised` (#faf9f7) bg — visually receded.
  Chronological bullets. Citations in `text-secondary`.

#### Section Changes

- **"What's Happening"** section → replaced by headline + "What's Going On"
- **"Recent Activity"** section → removed (redundant with Record)
- **"Key Decisions"** section → kept as-is (vote details with roll call)

### Per-Meeting TopicSummary Voice Update

The existing `analyze_topic_summary` and `render_topic_summary` prompts in
`OpenAiService` get updated to use the same editorial voice. The structured
`generation_data` JSON keeps its current schema. The rendered `content`
field shifts to the resident-facing editorial tone.

## Constraints

- Must align with TOPIC_GOVERNANCE.md (epistemic separation in generation,
  editorial synthesis in display)
- Must be cost-conscious — full regeneration only on minutes publication
- Must not fabricate continuity that doesn't exist in source documents
- Must not ascribe malice or damage individual reputations
- "Residents" not "locals" in all generated content
