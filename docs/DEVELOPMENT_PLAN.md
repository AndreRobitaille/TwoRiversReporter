# Two Rivers Meetings Transparency Site
## Software Development Plan

---

## Purpose

This project builds a public-facing website for residents of Two Rivers, WI to:

- See upcoming city meetings as early as possible
- Understand what is actually being discussed or decided
- Review past meetings, including minutes and voting behavior
- Hold elected officials and appointed boards accountable

The system ingests official city-published documents (PDFs and HTML),
preserves them as the source of truth, and produces clearly labeled,
citation-backed summaries for residents.

AI-generated content must never replace or obscure the official documents.

---

## Guiding Principles

1. PDFs are authoritative  
   HTML is used for discovery and structure. PDFs are the legal record.

2. Everything is optional  
   Not all meetings have packets, minutes, or video.

3. Progressive enrichment  
   Meetings become more useful over time as documents appear.

4. Explainability over cleverness  
   All summaries must include citations. External research must be labeled.

5. Single application  
   No microservices. No SPA. Server-rendered HTML with background jobs.

---

## Technology Stack

### Core
- Ruby on Rails
- PostgreSQL
- Server-rendered HTML (Rails views)
- Minimal JavaScript (Turbo/Hotwire only if needed)

### Background Processing
- ActiveJob
- Sidekiq or Solid Queue

### Parsing & Extraction
- Nokogiri (HTML parsing)
- pdftotext / pdfinfo (Poppler utilities)
- OCR (future, optional): Tesseract or equivalent

### Storage
- Local filesystem initially
- S3-compatible storage later if needed

---

## High-Level Architecture

City Website  
↓  
Meeting Index Pages  
↓  
Meeting Detail Pages (canonical records)  
↓  
Document Ingestion  
↓  
Text Extraction + Structuring (page-aware when possible)  
↓  
Summarization + Analysis  
↓  
Public Website  

---

## Core Domain Model

### Meeting
Represents a single official meeting.

Fields:
- body_name
- meeting_type
- starts_at
- location
- detail_page_url
- status (upcoming, held, minutes_posted)

### MeetingDocument
Represents any document associated with a meeting.

Fields:
- meeting_id
- document_type  
  (agenda_pdf, agenda_html, packet_pdf, packet_html, minutes_pdf, attachment_pdf)
- source_url
- fetched_at
- sha256
- storage_path
- page_count

Extraction-quality fields (to support legacy and scanned PDFs):
- text_chars (integer, total extracted characters from pdftotext)
- avg_chars_per_page (float, derived if page_count known)
- text_quality (string/enum: text, mixed, image_scan, broken)

### AgendaItem (optional)
Created only when packet HTML exists.

Fields:
- meeting_id
- order_index
- code
- title
- summary_text
- recommended_action

### AgendaItemDocument
Join table linking agenda items to attachment PDFs.

### Extraction
Stores page-aware text output.

Fields:
- meeting_document_id
- page_number
- raw_text
- cleaned_text

### Summary
Stores AI-generated content.

Fields:
- subject_type (meeting or agenda_item)
- subject_id
- summary_type  
  (agenda_overview, packet_grounded, minutes_summary, context_explainer)
- content_markdown
- citations_json
- generated_at

---

## Ingestion Workflow

### Step 1: Discover Meetings
- Crawl https://www.two-rivers.org/meetings
- Follow links to meeting detail pages
- Create or update Meeting records

### Step 2: Parse Meeting Detail Pages
- Extract date, time, body, location
- Detect document links by label
- Create MeetingDocument records

### Step 3: Download Documents
- Download PDFs and HTML
- Compute SHA-256 hashes
- Skip unchanged documents
- For PDFs:
  - Determine page_count (pdfinfo when available)
  - Run pdftotext and record text_chars and avg_chars_per_page
  - Classify text_quality:
    - text: avg_chars_per_page >= 200
    - mixed: 20 <= avg_chars_per_page < 200
    - image_scan: avg_chars_per_page < 20
    - broken: extraction error

### Step 4: Packet HTML Parsing (when available)
- Extract agenda items
- Extract summaries, recommended actions
- Extract attachment links
- Create AgendaItem and AgendaItemDocument records

### Step 5: PDF Text Extraction (Phase 2+)
- Extract text page by page (not required for Phase 1)
- Preserve page numbers
- Store raw and cleaned text

---

## Legacy PDFs and Document Quality

Older meeting PDFs may be:
- scanned image PDFs (no embedded text)
- low-quality Word-export PDFs
- inconsistent formatting across years/vendors

The system must:
- keep the original PDF as the source of truth
- record extraction quality (text_quality) for transparency
- avoid overpromising search/summaries when text_quality is poor

### OCR (future, not Phase 1)
OCR may be added later to improve searchability for image_scan PDFs, but:
- it is compute-heavy
- it can introduce transcription errors
- it must still support page-based citations and clear labeling

OCR should be:
- opt-in per document (or limited to high-interest bodies like City Council)
- scheduled asynchronously (never on a web request path)

---

## Summarization Rules

### Packet-Grounded Summaries
- Source: packet PDFs or attachment PDFs
- Must include page or document citations
- No external interpretation without labeling

### Agenda-Only Summaries
- Used when no packet exists
- Plain-language explanation of agenda items
- Highlight decisions and hearings

### Minutes Summaries
- Extract motions, votes, and discussion highlights
- Normalize member names
- Enable vote tracking

### Context Explainers
- Clearly labeled as external research
- Never mixed with packet-grounded claims

---

## Public Website Pages

### Home
- Upcoming meetings
- Recently posted minutes
- Recently updated meetings

### Meeting Page
- Meeting details
- Official documents
- Summaries when available
- Status indicators (packet posted, minutes pending, text quality)

### Body / Committee Pages
- Meeting history
- Common topics
- Attendance and voting summaries (future)

---

## Phased Development Plan

### Phase 1: Core Ingestion
- Meeting discovery
- Document storage
- Basic meeting pages
- Record PDF extraction quality metrics (text_quality, text_chars)

### Phase 2: Agenda & Packet Summaries
- Packet HTML parsing
- Page-cited summaries
- Resident explanations

### Phase 3: Minutes Analysis
- Vote extraction
- Member vote history

### Phase 4: Topic Aggregation
- Cross-meeting issue tracking
- Long-term accountability views

### Phase 5 (Optional): OCR for Legacy PDFs
- OCR pipeline for image_scan documents
- Clear labeling and citation support
- Opt-in scope controls and scheduling

---

## Current Implementation Status (2026-01-05)

### Phase 2: Agenda & Packet Summaries (In Progress)

Implemented so far:
- Agenda parsing: `Scrapers::ParseAgendaJob` parses `agenda_html` into `AgendaItem` records.
- PDF extraction quality + extracted text: `Documents::AnalyzePdfJob` runs `pdfinfo`/`pdftotext` and stores `text_quality` metrics.
- AI summaries (non-cited): `Documents::AnalyzePdfJob` triggers `SummarizeMeetingJob`, which calls `Ai::OpenAiService` and stores results in `MeetingSummary`.
- Meeting page display: `app/views/meetings/show.html.erb` renders the most recent `MeetingSummary`.

Gaps to complete Phase 2:
1. Page-aware extraction (required for citations)
   - Add an `Extraction` model/table to store `meeting_document_id`, `page_number`, `raw_text`, `cleaned_text`.
   - Update `Documents::AnalyzePdfJob` to preserve page boundaries (e.g., split `pdftotext` output on `\f`) and populate `Extraction` rows.
2. Agenda item attachments (required for packet-grounded summaries)
   - Add an `AgendaItemDocument` join model/table linking `agenda_items` to attachment `meeting_documents`.
   - Extend `Scrapers::ParseAgendaJob` to extract attachment links per agenda item and associate them to `MeetingDocument` records.
3. Cited summary generation
   - Update `Ai::OpenAiService` prompts to require citations like `[Page 3]` and only make claims supported by cited pages.
   - Pass page-scoped text (from `Extraction`) into the summarization prompt instead of one long blob.
4. Resident-friendly rendering
   - Render AI output as Markdown safely (current view uses `simple_format`, which treats Markdown as plain text).
   - Display citations with clear labels and always link back to original PDFs.

Operational follow-ups once the above is implemented:
- Re-run analysis/summarization for recent meetings to backfill cited summaries.
- Add basic guardrails: skip/label summaries when `text_quality` is `image_scan`/`broken`.

---

## Explicit Non-Goals

- No real-time streaming
- No commenting system
- No user accounts initially
- No moderation tools

---

## Quality Bar

The system must:
- Never fabricate decisions or votes
- Always link back to official documents
- Remain usable if AI features fail
- Be transparent about document text quality

---

## Instructions for AI Coding Tools

- Treat this document as authoritative
- Do not introduce new services or frameworks
- Prefer clarity over abstraction
- Ask before changing data models
- Never commit API keys/secrets; prefer `ENV`-driven configuration
