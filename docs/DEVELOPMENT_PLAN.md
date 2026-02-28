# Two Rivers Meetings Transparency Site

## Software Development Plan

------------------------------------------------------------------------

## Purpose

This project builds a public-facing website for residents of Two Rivers,
WI to:

- See upcoming city meetings as early as possible
- Understand what is actually being discussed or decided
- Review past meetings, including minutes and voting behavior
- Hold elected officials and appointed boards accountable

The system ingests official city-published documents (PDFs and HTML),
preserves them as the source of record, and produces clearly labeled,
citation-backed summaries for residents.

AI-generated content must never replace or obscure official documents.

------------------------------------------------------------------------

# Foundational Concept: Topics

This application is fundamentally a **civic topic tracking system**.

Meetings are the event stream.\
Documents are the artifacts.\
**Topics are the organizing structure.**

Resident entry is expected to be time-based (upcoming or recent meetings),
but the system must always reveal Topic continuity as the primary
explanatory layer.

Topics represent persistent civic concerns that:

- Span multiple meetings
- Cross governing bodies
- Accumulate motions, votes, deferrals, and disappearances
- Persist over months or years
- Reflect what residents care about

All topic-related modeling, extraction, inference, and presentation must
conform to:

**`docs/topics/TOPIC_GOVERNANCE.md`**

If implementation conflicts with Topic Governance, implementation must
change.

Summaries, knowledgebase context, and "What to Watch" features exist to
serve Topic continuity.

------------------------------------------------------------------------

## Guiding Principles

1. **PDFs are authoritative artifacts**\
    HTML is used for discovery and structure. PDFs are the legal record
    of what was published.

2. **Topics are primary; meetings are inputs**\
    Meeting-centric views are projections of Topic continuity.

3. **Progressive enrichment**\
    Meetings and Topics become more useful over time as documents
    appear.

4. **Explainability over cleverness**\
    All summaries must include citations. External research must be
    labeled.

5. **Structural skepticism, not editorializing**\
    The system surfaces patterns without assigning motive.

6. **Single application architecture**\
    No microservices. No SPA. Server-rendered HTML with background jobs.

------------------------------------------------------------------------

## Technology Stack

### Core

- Ruby on Rails
- PostgreSQL
- Server-rendered HTML
- Minimal JavaScript (Turbo/Hotwire only if needed)

### Background Processing

- ActiveJob
- Solid Queue

### Parsing & Extraction

- Nokogiri
- pdftotext / pdfinfo
- Tesseract (OCR)

### Storage

- ActiveStorage (local in dev, S3-compatible in production)

------------------------------------------------------------------------

## High-Level Architecture

City Website\
↓\
Meeting Discovery\
↓\
Document Ingestion\
↓\
Text Extraction + Structuring\
↓\
Topic Detection & Association\
↓\
Summarization (Topic-aware)\
↓\
Resident-Facing Pages

------------------------------------------------------------------------

## Core Domain Model

### Committee

Represents a governing body (city board, tax-funded nonprofit, or external
organization). Normalizes the free-form `body_name` string that the scraper
captures from the city website.

Key fields: - name - slug - description - committee_type (city,
tax_funded_nonprofit, external) - status (active, dormant, dissolved) -
established_on - dissolved_on

Committee descriptions are injected into AI prompts via
`OpenAiService#prepare_committee_context` so the AI understands what each
body does when generating summaries. Descriptions are editable via admin UI.

Related models:
- **CommitteeAlias** — Maps historical/variant names to canonical committee
  (e.g., "Splash Pad and Ice Rink Planning Committee" → "Central Park West
  365 Planning Committee"). Used by the scraper to resolve `body_name`.
- **CommitteeMembership** — Tracks which officials sit on which committees,
  with role, start/end dates, and source (ai_extracted, admin_manual, seeded).
  AI-driven extraction from meeting minutes via `ExtractCommitteeMembersJob`.
- **MeetingAttendance** — Per-meeting roll call record. Tracks who was
  present, absent, or excused at each meeting, with attendee type
  (voting_member, non_voting_staff, guest) and optional capacity title.
  Created by `ExtractCommitteeMembersJob` from meeting minutes.
  Drives automatic `CommitteeMembership` creation and departure detection.

### MemberAlias

Maps name variants to canonical Member records. Used by `Member.resolve`
to consolidate name variations from meeting minutes (e.g., "Council Rep
Adam Wachowski" → "Adam Wachowski", "Brandt" → "Doug Brandt").

Key fields: - member_id (FK) - name (unique)

Admin-managed via `/admin/members`. Auto-created by `Member.resolve` for
unambiguous last-name-only entries.

### Meeting

Represents a single official meeting. Belongs to a Committee (optional).

Key fields: - body_name (historical, as scraped) - committee_id (FK) -
meeting_type - starts_at - location - detail_page_url - status

### MeetingDocument

Represents any document associated with a meeting.

Key fields: - meeting_id - document_type - source_url - sha256 -
page_count - text_quality - extracted_text

### Topic (Foundational)

Represents a long-lived civic concern.

Key fields: - canonical_name - slug - status (active, dormant,
resolved) - first_seen_at - last_seen_at - description
(AI-generated, admin-overridable) - description_generated_at

Topics must: - Support aliases - Support sub-topics - Track cross-body
continuity - Derive status from agenda recurrence + resolution signals

### AgendaItemTopic (Join)

Links agenda items or meeting events to Topics.

### MeetingSummary

AI-generated content grounded in documents and Topic context.

------------------------------------------------------------------------

## Ingestion Workflow

1. Discover meetings
2. Parse detail pages
3. Download documents
4. Extract text (classify quality)
5. Parse packet HTML (if available)
6. Associate agenda items to Topics
7. Update Topic continuity metrics

------------------------------------------------------------------------

## Topic Granularity

The extraction prompt classifies agenda items into **categories**
(Zoning, Infrastructure, Finance, etc.) and **topic tags**. Categories
describe process domains; topic tags must name specific civic concerns.

**Category names are never valid topic names.** They are blocked in
the `TopicBlocklist` and the extraction prompt explicitly forbids them.
A topic must be specific enough to tell a coherent story over time.

| Level | Example | Valid topic? |
|-------|---------|-------------|
| Category (too broad) | "zoning", "infrastructure", "finance" | No |
| Civic concern | "conditional use permits", "city budget", "street paving" | Yes |
| Hyper-specific | "123 Main St survey map" | No |
| Routine/one-off | single plat review, standard license renewal | Not topic-worthy |

**The test:** "Would a resident follow this topic across multiple
meetings?" If the answer only makes sense for a specific concern within
the category, name that concern. If the item is routine, it's not
topic-worthy.

### Cleanup tools

- `bin/rails topics:seed_category_blocklist` — adds all category names
  to the blocklist (idempotent).
- `bin/rails topics:split_broad_topic[name]` — re-extracts agenda items
  from a named broad topic. Each item is re-classified into a specific
  topic or marked not topic-worthy. New topics go through normal triage.

------------------------------------------------------------------------

## Topic Descriptions

Topics have short (~80 char) descriptions displayed on topic cards and
detail pages. These are auto-generated by AI and periodically refreshed.

### How descriptions are generated

`Topics::GenerateDescriptionJob` uses `Ai::OpenAiService#generate_topic_description`
with the `LIGHTWEIGHT_MODEL` (gpt-5-mini) to produce a one-sentence scope
description. The prompt is tiered:

- **3+ agenda items**: Activity-informed — AI reads item titles/summaries
  and describes what the topic covers based on observed activity patterns.
- **Fewer than 3**: Broad civic-concept — AI writes a general description
  of the civic topic without anchoring to specific events.

Guardrails: max 80 chars, scope not event, no addresses/names/dates,
plain neighborhood language.

### When descriptions are generated

- **On approval**: Automatically enqueued when a topic is approved
  (via TriageTool auto-approval, admin single approve, or admin bulk approve).
- **Weekly refresh**: `Topics::RefreshDescriptionsJob` runs every Monday
  at 3am (config/recurring.yml). Regenerates descriptions older than 90
  days and generates missing ones.
- **Manual backfill**: `bin/rails topics:generate_descriptions` processes
  all approved topics with missing descriptions synchronously.

### Admin override

If an admin manually edits a description in the admin form,
`description_generated_at` is set to nil. This permanently prevents the
refresh job from overwriting it. To re-enable AI generation for a topic,
set `description_generated_at` to a past date or clear the description.

### Key files

- `app/services/ai/open_ai_service.rb` — `generate_topic_description` method
- `app/jobs/topics/generate_description_job.rb` — per-topic generation
- `app/jobs/topics/refresh_descriptions_job.rb` — weekly sweep scheduler
- `lib/tasks/topics.rake` — `topics:generate_descriptions` backfill task
- `config/recurring.yml` — schedule entry

------------------------------------------------------------------------

## Topic Lifecycle

Topics move through states based on observable signals:

- **Active** -- Appears on recent agendas or under active discussion
- **Dormant** -- No recent activity but historically significant
- **Resolved** -- Formal decision reached (vote, ordinance adoption,
    abandonment)
- **Recurring** -- Previously resolved but resurfaced

Status derivation must: - Prefer agenda anchors - Treat disappearance
without resolution as meaningful - Avoid assuming resolution without
evidence

------------------------------------------------------------------------

## Summarization Rules

Summaries must:

- Separate document-grounded claims from background context
- Cite packet pages or meeting pages when possible
- Use verified knowledgebase facts only
- Never infer motive
- Surface recurrence and deferral patterns

Topic-aware summaries should: - Reference prior relevant meetings -
Indicate duration of issue - Note governing body progression (committee
→ council)

### Editorial Voice

All resident-facing summaries use a neighborhood-reporter voice:

- **Skeptical of process and decisions, not of people.** Question what's
  being done and why. Don't name-and-shame or ascribe bad intent.
- **Editorialize early.** Casual residents can't connect the dots
  themselves — the summary does that work for them.
- **Plain language.** Translate jargon ("general obligation promissory
  notes" → "borrowing"). Write for phone scanners, not policy wonks.
- **Resident impact first.** Cost, timeline, who's affected, what
  changes in the neighborhood — this is what people care about.
- **No procedural noise.** Motions, seconds, and roll-call details
  belong in Key Decisions, not in narrative summaries.

### Two-Pass Generation Architecture

Full-quality summaries (both per-meeting `TopicSummary` and rolling
`TopicBriefing`) use a two-pass architecture:

**Pass 1 — Structured Analysis** (`analyze_topic_briefing` /
`analyze_topic_summary`): gpt-5.2 with `response_format: json_object`.
Produces structured JSON with editorial analysis, factual record, civic
sentiment, continuity signals, and resident impact scoring (1–5 scale).
Knowledgebase context is included here to inform analysis.

**Pass 2 — Markdown Rendering** (`render_topic_briefing` /
`render_topic_summary`): gpt-5.2 takes the Pass 1 JSON and renders
resident-facing markdown. Produces two distinct sections:

- **Editorial** ("What's Going On"): 100–200 word prose. Analytical,
  skeptical, no inline citation IDs. Reads cleanly as narrative.
- **Record**: Chronological bullet list. Each bullet ends with meeting
  name and date in parentheses (not internal IDs). Factual only.

Internal structural categories (Factual Record, Institutional Framing,
Civic Sentiment) exist in the analysis JSON but are **never exposed** in
rendered output. The rendering pass synthesizes them into unified
editorial prose.

### Citation Rules

- Per-meeting summaries cite packet pages: `[Packet Page 12]`
- Rolling briefing record bullets cite meeting names: `(Council, Feb 18)`
- Internal IDs (e.g., `[agenda-309]`) are never shown to residents
- Citation translation happens at the prompt level, not post-processing

### Three-Tier Briefing Pipeline

See `docs/plans/2026-02-21-topic-briefing-architecture-design.md` for
full design. Summary:

| Tier | Trigger | AI Cost | Output |
|------|---------|---------|--------|
| `headline_only` | Future meeting scheduled | None | Derived headline |
| `interim` | Agenda/packet added | 1× gpt-5-mini | Updated headline + upcoming note |
| `full` | Minutes published | 2× gpt-5.2 | Full editorial + record + headline |

------------------------------------------------------------------------

## Knowledgebase + Contextual Summaries

Purpose: Provide relevant historical and structural background without
overwhelming prompts.

Constraints:

- Only verified facts may appear in resident-facing summaries
- Sensitive relationships must be gated
- Stance tracking limited to public commenters
- Retrieval must be capped and relevance-scored

Integration: KB context is fed into Pass 1 (analysis) of the two-pass
pipeline via `Topics::SummaryContextBuilder`. It informs editorial
analysis but is distinguished from document content in the prompt.

------------------------------------------------------------------------

## Public Website Structure

### Home

- Upcoming meetings (primary entry)
- Recently updated Topics (continuity cues)
- "What to Watch" (Topic-driven)

### Topic Page (Primary Lens)

- Topic description (auto-generated, max 80 chars)
- Briefing headline (bold, warm card)
- Coming Up cards (future meetings with this topic)
- "What's Going On" editorial (prose, 100–200 words)
- "Record" (chronological cited bullets spanning all meetings)
- Key Decisions (motions with vote breakdowns)
- Related documents
- Status/lifecycle indicators

### Meeting Page

- Meeting details
- Official documents
- Topic Analysis (AI-generated per-topic summaries, collapsible)
- Meeting Recap / Packet Analysis (AI-generated meeting-level summary)
- Voting Record (motions with vote breakdowns)
- Agenda (with inline topic tags linking to topic pages)
- Documents (PDFs, originals)
- **Issues in This Meeting** — topic cards split into two subsections:
  - *Ongoing*: topics with 2+ meeting appearances ("These issues have
    come up across multiple meetings. Click any for the full picture.")
  - *New This Meeting*: topics appearing for the first time
  - Reuses the standard `_topic_card` partial (same cards as homepage
    and topics index) for consistent navigation
  - Only shows approved topics; skips section entirely if none exist

### Navigation: Topic Click-Through Behavior

Topic navigation follows these principles:

- **Topic cards are the primary discovery path.** The same card partial
  (`topics/_topic_card`) is used on the homepage, topics index, and
  meeting pages. Clicking any card goes to `/topics/:id`.
- **Meeting pages bridge to topics via the "Issues in This Meeting"
  section** placed after documents. Residents who read a meeting's AI
  analysis can discover deeper topic history through these cards.
- **Topic summary headers are not clickable.** AI-generated prose uses
  different language than canonical topic names, and the interaction
  wouldn't be apparent to residents unfamiliar with the topic concept.
- **Homepage meeting rows show topic pills filtered by importance.**
  Only approved topics with `resident_impact_score >= 2` appear as
  pills. No count cap, no overflow indicator. Empty cells are fine.
- **Agenda item topic tags** remain as inline links to topic pages
  (contextual, secondary navigation).

------------------------------------------------------------------------

## Quality Bar

The system must:

- Never fabricate decisions or votes
- Always link to official documents
- Remain usable if AI fails
- Be transparent about extraction quality
- Preserve long-term civic memory

------------------------------------------------------------------------

## Instructions for AI Coding Tools

- Treat this document as authoritative.
- **Before any work, also read these two documents:**
    - **`docs/AUDIENCE.md`** — Who uses this site, how they behave,
      and what they care about. All UI, content, and prioritization
      decisions must account for this audience.
    - **`docs/topics/TOPIC_GOVERNANCE.md`** — Binding rules for all
      topic extraction, classification, summarization, and lifecycle
      logic.
- The next engineering work must start with `docs/topic-first-migration-plan.md`.
- Treat `docs/topics/TOPIC_GOVERNANCE.md` as binding for all Topic
    logic.
- Meetings are inputs. Topics are the organizing layer.
- Do not introduce new services or frameworks.
- Prefer clarity over abstraction.
- Ask before changing data models.
- Never commit secrets.
- For topic cleanup automation and triage runs, see `docs/topic-triage-tool.md`.
