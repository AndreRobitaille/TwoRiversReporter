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

### Meeting

Represents a single official meeting.

Key fields: - body_name - meeting_type - starts_at - location -
detail_page_url - status

### MeetingDocument

Represents any document associated with a meeting.

Key fields: - meeting_id - document_type - source_url - sha256 -
page_count - text_quality - extracted_text

### Topic (Foundational)

Represents a long-lived civic concern.

Key fields: - canonical_name - slug - status (active, dormant,
resolved) - first_seen_at - last_seen_at - description
(admin-controlled)

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

------------------------------------------------------------------------

## Knowledgebase + Contextual Summaries

Purpose: Provide relevant historical and structural background without
overwhelming prompts.

Constraints:

- Only verified facts may appear in resident-facing summaries
- Sensitive relationships must be gated
- Stance tracking limited to public commenters
- Retrieval must be capped and relevance-scored

------------------------------------------------------------------------

## Public Website Structure

### Home

- Upcoming meetings (primary entry)
- Recently updated Topics (continuity cues)
- "What to Watch" (Topic-driven)

### Topic Page (Primary Lens)

- Topic description
- Timeline of meetings
- Motions and votes
- Related documents
- Status indicator
- Upcoming agenda appearances

### Meeting Page

- Meeting details
- Official documents
- Topic associations
- Summaries
- Pivot to Topic continuity (agenda items link to Topic timeline)

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
- The next engineering work must start with `docs/topic-first-migration-plan.md`.
- When beginning any topic-related task, read `docs/topics/TOPIC_GOVERNANCE.md` first.
- Treat `docs/topics/TOPIC_GOVERNANCE.md` as binding for all Topic
    logic.
- Meetings are inputs. Topics are the organizing layer.
- Do not introduce new services or frameworks.
- Prefer clarity over abstraction.
- Ask before changing data models.
- Never commit secrets.
