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

### Contextual Summaries (Knowledgebase / RAG)
- Purpose: provide relevant background (prior meetings, people/org/project history, city plans) without large context windows.
- Inputs:
  - Verified facts (admin-only knowledgebase).
  - Retrieved excerpts from ingested PDFs/notes (top-k, capped per source).
  - Prior-meeting history derived from the database.
- Rules:
  - Resident-facing content may use only `verified` knowledgebase facts.
  - "Sensitive" facts must be gated and included only when directly relevant.
  - Store stance/sentiment only for public commenters; do not infer officials' private sentiment.
  - Document-grounded claims must be cited; background context must be labeled as background.

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

### Phase 1: Core Ingestion (Completed)
Implemented:
- Meeting discovery
- Document storage
- Basic meeting pages
- Text quality metrics

### Phase 2: Agenda & Packet Summaries (Completed)
Implemented:
- Packet HTML parsing
- Page-cited AI summaries
- Page-aware extraction

### Phase 3: Minutes Analysis (Completed)
Implemented:
- Vote extraction
- Member profiles

### Phase 4: Topic Aggregation (Completed)

Implemented:
- Topic models: `Topic`, `AgendaItemTopic`.
- Issue categorization: `ExtractTopicsJob` tags agenda items with high-level categories (Governance, Finance, etc.).
- Member profiles: `MembersController` and views for listing officials and their voting history.
- Topic exploration: `TopicsController` and views for browsing items by issue.

### Phase 5: OCR for Legacy PDFs (Completed)

Implemented:
- Tesseract integration: Added `tesseract-ocr` to Dockerfile.
- OCR pipeline: `OcrJob` converts PDF pages to images and extracts text.
- Automatic triggering: `AnalyzePdfJob` detects "image_scan" quality and queues OCR.
- Data enrichment: OCR'd text automatically triggers summarization and vote extraction.

### Phase 6: Knowledgebase + Contextual Summaries (Planned)

Goal: Improve meeting summaries by incorporating relevant local context (prior meetings, people/org/project history, city plans) while keeping API cost predictable. Residents never see the knowledgebase content itself.

#### Prerequisite: Admin Authentication (Completed)
- Implemented Rails-native authentication (User model + sessions).
- Added admin-only namespace (`/admin`) and dashboard.
- Enforced TOTP MFA for all admin accounts (using `rotp`).
- Provided offline recovery codes for emergency access.
- Styled auth forms to match application design.

#### Knowledgebase Requirements
- Admin-only knowledgebase
  - Primary input: freeform typed notes.
  - Secondary input: PDFs (e.g., Comprehensive Plan, Economic Plan, local history), ingested into searchable chunks.
  - Knowledge entries support verification metadata (admin-only): `status`, `verified_on`, `verification_notes`.
- Retrieval-augmented generation (RAG)
  - Never send large static context windows to the LLM.
  - Chunk and embed knowledge sources once; retrieve only the top relevant chunks for each meeting.
  - Apply hard caps (total chunks, per-source chunks) and similarity thresholds to control prompt size.
- Entity memory (admin-controlled)
  - The system may extract and suggest entities from meeting documents (JSON mode) but must not automatically publish these as resident-facing "facts".
  - Entity matching must support misspellings (aliases) and disambiguation (admin-only fields such as address or affiliation).
- Facts and relationships
  - The system may draft facts/relationships in "draft" status for admin review.
  - Only "verified" facts may be used in resident-facing summaries.
  - "Sensitive" facts (e.g., family relationships, ownership/financial ties) must be gated and included only when directly relevant to the meeting subject.
- Public comment memory (limited scope)
  - Store stance/sentiment only for public commenters (not officials).
  - Officials' statements and vague "received emails" references are not stored as stance.
  - Stance observations must be backed by evidence snippets and meeting/document references.
- Resident feedback loop
  - Residents can submit "correction / missing context" requests from a summary.
  - Requests are stored for admin review and can trigger knowledgebase updates and summary regeneration.

Summarization behavior changes:
- Meeting summaries must clearly separate:
  - Document-grounded claims (cited to meeting pages when available).
  - Background context (from verified knowledgebase facts/excerpts).
- Background facts must be included only when relevant to the meeting subjects (agenda items/topics/entities). Unrelated biographical trivia must be omitted.

---

## Explicit Non-Goals
- No real-time streaming
- No commenting system
- No resident user accounts (admin accounts are allowed)
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
