# Issue 50: Topic-aware retrieval context + caps

## Goal
Make knowledgebase retrieval topic-centric, deterministic, and explicitly capped, with clear provenance labeling for verified vs unverified sources.

## References
- `docs/DEVELOPMENT_PLAN.md`
- `docs/topics/TOPIC_GOVERNANCE.md`
- GitHub Issue #50

## Constraints (from governance + issue)
- Retrieval must be topic-aware and avoid non-topic leakage.
- Context caps must be explicit (count and size).
- Provenance labeling must be surfaced in prompts (verified vs unverified).
- Behavior must be deterministic and explainable.

## Current State (as of 2026-02-16)
- `RetrievalService` embeds a query and returns top-k `KnowledgeChunk` records by cosine similarity.
- `Topics::RetrievalQueryBuilder` builds topic/appearance/agenda query text, but retrieval still scans all active sources.
- `RetrievalService#format_context` labels trust based on `knowledge_source.verification_notes`.
- Topic summaries call `retrieve_context` with a limit of 5, but no topic-based filtering or explicit size caps.
- `KnowledgeSource`/`KnowledgeChunk` linked to `Topic` via `knowledge_source_topics` (many-to-many).

## Proposed Approach
1) Add topic-aware retrieval filtering
   - Introduce a topic-scoped retrieval entry point (e.g., `retrieve_topic_context(topic:, meeting:, limit:, max_chars:)`).
   - Restrict candidate `KnowledgeChunk` rows to those linked to the topic or matching topic metadata.
   - Prefer explicit associations (e.g., `knowledge_source.topic_id` or join table) if present; otherwise define a safe fallback that only uses topic names/aliases.

2) Add explicit caps
   - Enforce a hard cap on number of chunks (count).
   - Enforce a size cap in characters for total retrieved context (truncate or drop least relevant chunks).
   - Make caps configurable constants in `RetrievalService` or `Topics::RetrievalQueryBuilder`.

3) Deterministic and explainable retrieval
   - Sort ties deterministically (e.g., by score desc, then chunk id asc).
   - Return provenance metadata per chunk (source id, verification status, topic linkage).
   - Document retrieval behavior inline and in plan updates.

4) Prompt labeling
   - Ensure formatted context clearly labels each chunk as verified/unverified.
   - Add source type/provenance tags to prevent mixing verified facts with unverified background.

## Implementation Tasks
1. [x] Audit data model for topic-to-knowledge mapping
   - Search for `KnowledgeSource` / `KnowledgeChunk` associations.
   - Confirm whether topics are linked to knowledge sources. (No direct link found)
   - Decide on safe fallback filter if no explicit linkage exists. (Rely on vector search + strict caps)

2. [x] Extend `RetrievalService`
   - Add topic-aware retrieval method with filter + caps (`retrieve_topic_context`).
   - Ensure deterministic ordering of results (Score DESC, ID ASC).
   - Update formatting to include provenance labels (`format_topic_context`).

3. [x] Update `SummarizeMeetingJob`
   - Use the topic-aware retrieval path for topic summaries.
   - Keep meeting-level retrieval unchanged unless explicitly required.

4. [x] Update tests
   - Add/extend tests for topic retrieval filtering, caps, and deterministic ordering.
   - Ensure existing `SummarizeMeetingJob` tests still pass.

5. [x] Document behavior
   - Add inline docs in `RetrievalService` and/or `Topics::RetrievalQueryBuilder`.
   - Update relevant docs if needed (only if changes are user-facing).

6. [x] Add Schema Linkage
   - Added `KnowledgeSourceTopic` join table.
   - Added `KnowledgeSource#topics` and `Topic#knowledge_sources`.
   - Implemented `rake topics:backfill_knowledge_sources` for heuristic linking.
   - Updated `retrieve_topic_context` to filter by topic ID.

## Open Questions
- Is there an existing schema link between `Topic` and `KnowledgeSource`/`KnowledgeChunk`? If not, what is the approved linkage pattern? (No link currently. Deferred schema change.)
- Preferred cap values (count and max chars) for topic summaries? (Decided: 5 chunks, 6000 chars)
- Should meeting-level summaries remain global or become body-scoped? (Remaining global for now)

## Validation
- Run `bin/rails test test/jobs/summarize_meeting_job_test.rb`. (Passed)
- Add targeted service tests for retrieval filtering and caps. (`test/services/retrieval_service_test.rb` Passed)
