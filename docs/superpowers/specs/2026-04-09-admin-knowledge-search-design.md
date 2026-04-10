# Admin Knowledge Search

**Date:** 2026-04-09
**Status:** Design approved
**Scope:** Admin-only RAG search page with AI synthesis and source traceability

## Problem

The knowledge base contains extracted facts, patterns, and manual notes about Two Rivers civic governance — committee memberships spanning decades, policy decisions, personnel changes. There's no way to query this information interactively. An admin should be able to ask "Who has served longest on Plan Commission?" and get an answer with traceable citations back to the originating meeting documents.

## Design

### Overview

Single admin page at `GET /admin/search`. Two search layers:

1. **Knowledge Base** — vector similarity search via `RetrievalService` over `KnowledgeChunk` embeddings
2. **Meeting Documents** — PostgreSQL full-text search via existing `MeetingDocument.search` scope

Optional AI synthesis: an "Ask AI" button sends the query + top KB chunks to gpt-5.2, which returns a prose answer with numbered citations. Each citation links to the KB source admin page and (for newer sources) the originating meeting.

### Architecture

**Route:** `resource :search, only: [:index], controller: "searches"` inside the admin namespace. Gives `GET /admin/search`.

**Controller:** `Admin::SearchesController < Admin::BaseController`

Single `index` action:
- Empty `params[:q]`: render form only
- Query present:
  - `@kb_results = RetrievalService.new.retrieve_context(params[:q], limit: 10)` — returns `[{ chunk:, score: }]`
  - `@document_results = MeetingDocument.search(params[:q]).includes(:meeting).limit(10)`
  - If `params[:ask_ai]`: `@ai_answer, @citations = Ai::OpenAiService.new.answer_question(params[:q], kb_chunks, source: "admin_search")`

**No Turbo frames** for v1 — standard form submission, full page re-render.

### OpenAiService Changes

**Model upgrade:** `LIGHTWEIGHT_MODEL` constant changes from `"gpt-5-mini"` to `"gpt-5.4-mini"`. Both do not support the `temperature` parameter — existing guard logic is unchanged. All callers of `LIGHTWEIGHT_MODEL` pick up the new model automatically.

**New method:** `answer_question(query, context_chunks, source:)`
- Uses `DEFAULT_MODEL` (gpt-5.2) — accuracy matters for investigative queries
- Loads prompt from `PromptTemplate` named `knowledge_search_answer`
- Interpolates `{{context}}` (formatted chunks via `prepare_kb_context`) and `{{question}}`
- Instructs the model to cite sources by number (`[1]`, `[2]`, etc.)
- Returns plain text answer (prose for humans, not JSON)
- Logged via `record_prompt_run` like all other LLM calls

### PromptTemplate Seed

New template: `knowledge_search_answer`

- **system_role:** "You are a research assistant for a civic transparency project in Two Rivers, WI. Answer questions using only the provided knowledge base context. Cite sources by number in brackets (e.g. [1], [2]). If the context doesn't contain enough information to answer confidently, say so clearly. Be direct and specific."
- **instructions:** "Context:\n{{context}}\n\nQuestion: {{question}}\n\nAnswer the question based on the context above. Cite each factual claim with a numbered source reference in [brackets]. Be direct and specific."

Seeded via existing `db/seeds.rb` pattern alongside the other prompt templates.

### Citation Design

The AI answer uses numbered references (`[1]`, `[2]`). The `answer_question` method numbers the context chunks in the order they're passed (chunk 0 → `[1]`, chunk 1 → `[2]`, etc.) and instructs the model to use those numbers. The method returns two values: the answer text (string) and the ordered array of chunks used as context. The controller zips the chunk array into a citation index for the view.

The view renders citations as footnotes below the answer. Each footnote shows:
- **Source title** as a link to `/admin/knowledge_sources/:id`
- **Origin badge** (manual / extracted / pattern)
- **`stated_at` date** if present
- **Meeting link** if `knowledge_source.meeting_id` is present — links to the public meeting page

Example rendering:
> Kay Koch served on Plan Commission for approximately 38 years [1]. Her daughter Tracey Koch was appointed to replace her [2].
>
> **Sources:**
> 1. [Plan Commission membership patterns](/admin/knowledge_sources/42) — *extracted* · stated 2025-11-15
> 2. [November 2025 Council Meeting](/admin/knowledge_sources/58) — *extracted* from [Council Meeting Nov 20, 2025](/meetings/123)

### KnowledgeSource: meeting_id FK

**Migration:** Add nullable `meeting_id` FK to `knowledge_sources` table with an index.

**Model:** `belongs_to :meeting, optional: true` on `KnowledgeSource`. `has_many :knowledge_sources` on `Meeting`.

**ExtractKnowledgeJob:** Add `meeting_id: meeting.id` to the `create_knowledge_source` call. One-line change — the `meeting` object is already available.

**ExtractKnowledgePatternsJob:** No change — pattern-derived sources are synthesized across multiple meetings and correctly remain without a meeting_id.

**No backfill.** Existing extracted sources stay without `meeting_id`. The search citations fall back to showing `stated_at` date without a meeting link. New extractions going forward will have the FK. The gap fills naturally as meetings are re-processed.

### View & UI

Silo theme. All existing design system components — no new CSS classes except `.card--ai-answer` (teal left border).

**Page structure:**

1. **Header** — `page-header` with title "Knowledge Search", subtitle "Ask questions about your civic data"

2. **Search bar** — `card` containing `search-form`:
   - Full-width text input
   - "Search" button (`btn--secondary`) — semantic search only, fast/free
   - "Ask AI" button (`btn--primary`) — search + gpt-5.2 synthesis

3. **AI Answer** (conditional, only when `ask_ai=true` and results exist):
   - `card` with `border-left: 3px solid var(--color-teal)`
   - Header: "AI Answer" in `badge badge--info`
   - Body: prose-formatted answer text
   - Citations as numbered footnotes with source links, origin badges, meeting links
   - Footer: `text-sm text-muted` — model name and chunk count ("Based on 7 knowledge sources · gpt-5.2")

4. **Knowledge Base Results** — `card` with header "Knowledge Base Results (N)":
   - Each result as a row (not a table — content too variable):
     - Similarity score as percentage in `font-data` (DM Mono)
     - Source title as link to `/admin/knowledge_sources/:id`
     - Origin badge (`badge--info` extracted, `badge--default` manual, `badge--warning` pattern)
     - Content preview (~200 chars), `text-sm text-secondary`
     - `stated_at` date if present, `font-data text-muted`

5. **Meeting Document Results** — `card` with header "Meeting Documents (N)":
   - Each result as a row:
     - Document type badge (minutes/packet/transcript/agenda)
     - Meeting name + date as link to public meeting page
     - Text excerpt with highlighted matches via PostgreSQL `ts_headline`, `text-sm`
     - Committee name in `text-muted`

6. **Empty states:**
   - No query: `section-empty` — "Enter a search to query the knowledge base and meeting documents"
   - No results: `section-empty` — "No matching results found"

**No pagination** for v1 — 10 KB + 10 document results is manageable.

**Dashboard link:** Add "Knowledge Search" to the Content section of the admin dashboard.

### Testing

**Controller test:** `Admin::SearchesControllerTest`
- Empty state: `GET /admin/search` renders form without errors
- With query: `GET /admin/search?q=plan+commission` returns KB and document results
- With ask_ai: `GET /admin/search?q=plan+commission&ask_ai=true` calls `answer_question`, renders AI answer card
- Auth: unauthenticated users redirected to login

**Service test:**
- `OpenAiService#answer_question` — stub API, verify correct prompt template with context/question, returns answer text
- Verify it uses `DEFAULT_MODEL` (gpt-5.2)

**Model test:**
- `KnowledgeSource` has optional `belongs_to :meeting`

### Files to Create/Modify

| Action | File |
|--------|------|
| Create | `app/controllers/admin/searches_controller.rb` |
| Create | `app/views/admin/searches/index.html.erb` |
| Create | `db/migrate/XXX_add_meeting_id_to_knowledge_sources.rb` |
| Create | `test/controllers/admin/searches_controller_test.rb` |
| Modify | `config/routes.rb` — add search resource to admin namespace |
| Modify | `app/services/ai/open_ai_service.rb` — add `answer_question` method, update `LIGHTWEIGHT_MODEL` |
| Modify | `app/models/knowledge_source.rb` — add `belongs_to :meeting, optional: true` |
| Modify | `app/models/meeting.rb` — add `has_many :knowledge_sources` |
| Modify | `app/jobs/extract_knowledge_job.rb` — add `meeting_id:` to create call |
| Modify | `app/views/admin/dashboard/show.html.erb` — add search link |
| Modify | `db/seeds.rb` or `db/seeds/prompt_templates.rb` — add `knowledge_search_answer` template |
| Modify | `app/assets/stylesheets/application.css` — add `.card--ai-answer` (one rule) |
| Modify | `test/services/ai/open_ai_service_test.rb` — add `answer_question` test |
| Modify | `test/models/knowledge_source_test.rb` — add meeting association test |
