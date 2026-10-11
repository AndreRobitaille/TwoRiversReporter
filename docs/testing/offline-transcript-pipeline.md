# Offline transcript preservation

This scenario follows the approved July 7 SRT upload workflow, the September 30 evidence-preservation update to the April 9 transcript design, Topic Governance and AGENTS.md. It addresses the integrated boundary in #168 and #183. It does not establish native OCR, YouTube retrieval, real AI output or production worker/delivery behavior.

## Exact journeys and fixture boundary

- `Admin::OfflineTranscriptPipelineTest#test_real_uploaded_transcript_stages_retain_both_identities_source_versions_and_closing_evidence_on_rerun`
- `Admin::OfflineTranscriptPipelineTest#test_mid_extraction_failure_removes_partial_new_identities_and_restores_old_links_before_a_usable_retry`
- `TranscriptPipelineJourneysTest#test_admin_uploads_a_transcript_and_the_queued_real_pipeline_reaches_both_resident_topics_and_sources`

The fixture contains one structural row, two distinct substantive items and approved topics, official minutes, an official tabled motion with no votes, and a 52,215-character UTF-8 SRT body with a closing evidence marker. The browser uses the actual admin navigation, multipart upload, CSRF-protected form, queued job arguments, completed import/log display, meeting and both topic pages, and rendered source/meeting links. Captured email authenticates the synthetic admin; a seeded passkey row supplies eligibility only.

Only the `Ai::OpenAiService` and `Ai::EmbeddingService` provider objects return deterministic local fixtures. The importer, meeting summarizer, hollow-appearance pruning, topic extraction/reanalysis, retrieval/vector storage, context builders, citation validation/resolution, continuity and briefing generation execute real business code. `perform_enqueued_jobs(only: Admin::TranscriptImportWorkflowJob)` executes the actual serialized import job; inline summary/reanalysis/continuity/briefing stages are real. Other callback jobs remain in Active Job's test queue; the failure case checks that a genuinely created partial appearance queued its continuity callback. This is not a Solid Queue worker scheduling test. Mail uses the test adapter and storage uses the worktree's test disk.

## Evidence at each boundary

Provider input assertions compare the uploaded document ID, full extracted text, Unicode character count, raw SRT bytes/MD5 attachment checksum, transcript SHA-256/source catalog, complete trailing marker, actual item/topic pairs and official motion context. Meeting-summary persistence retains both item identities and their different facts, minutes-recap/source type, catalog and absent invented votes. Extraction receives both substantive IDs and excludes the structural ID. Each topic and briefing receives its own item/fact and canonical source references. Final summaries and briefings resolve to the actual official-minutes or whole-source transcript document; model-supplied URLs are discarded. Official minutes and motion attributes remain unchanged.

Rerunning replaces the transcript document while retaining item/topic/appearance/summary/briefing identities. A completed historical import loses only its optional deleted-document pointer: status, logs, affected IDs, timestamps and original SRT upload remain intact. A malformed second classification fails after creating a real partial association. The workflow records failure, restores the old links and appearances, removes the partial new ones, preserves official records, and completes on a subsequent usable retry.

## Defects and restored experiments

The pre-fix scenarios reproduced a byte-based Unicode `text_chars` value, reanalysis that overwrote canonical references/catalog, and a PostgreSQL foreign-key failure when replacing a document referenced by a completed import. The fixes label uploaded text UTF-8, apply the existing topic citation-copy/catalog contract during reanalysis, and nullify the nullable historical document reference on deletion. No schema or prompt change is needed.

After a clean baseline, each isolated fault failed its intended assertion with one failure, zero errors and zero skips:

| Fault | Detected boundary |
|---|---|
| Remove UTF-8 encoding | Exact character count |
| Omit reanalysis canonical references/catalog | Catalog and canonical source provenance; job and browser |
| Truncate supplementary context to 20,000 characters | Full trailing transcript at meeting-analysis input |
| Retain only the first extracted classification | Both distinct item/topic pairs; job and browser |
| Remove historical reference nullification | Actual rerun completes, rather than foreign-key failure |
| Omit old-link restoration after extraction failure | Persistent original link pairs |
| Omit partial-appearance cleanup | Complete original appearance identities and attributes |

A test-only namespace error in a newly added callback assertion was corrected before counting rollback fault results; it is not defect-detection evidence. One external log verifier expected `Expected:` while Minitest emitted a structured `--- expected` diff; the underlying cleanup assertion failed correctly. All temporary application faults were restored and the complete targeted and browser suites rerun.

## Commands and isolation

From the isolated candidate worktree, the external `run-pipeline` wrapper fixes `RAILS_ENV=test`, `DATABASE_URL=postgresql:///trr_pipeline_20261010_test`, `PARALLEL_WORKERS=1`, writable external gem/lint caches and a provider-network guard. It unsets inherited provider/database credentials. No production data or secrets are copied.

```sh
run-pipeline bin/rails test test/jobs/admin/offline_transcript_pipeline_test.rb test/services/documents/uploaded_transcript_importer_test.rb test/services/topics/meeting_reanalysis_service_test.rb
CHROME_BIN=/usr/bin/chromium run-pipeline bin/rails test:system
run-pipeline bin/rubocop app/models/meeting_document.rb app/services/documents/uploaded_transcript_importer.rb app/services/topics/meeting_reanalysis_service.rb test/jobs/admin/offline_transcript_pipeline_test.rb test/support/offline_transcript_pipeline.rb test/system/transcript_pipeline_journeys_test.rb
CHROME_BIN=/usr/bin/chromium run-pipeline bin/ci
```

Run ordinary and browser suites serially against this database. Local runtime is Ruby 4.0.7, PostgreSQL 18.6 and matching Chromium/chromedriver 152. GitHub CI supplies PostgreSQL 17 and matching Chrome/driver. Candidate and combined-master counts/revisions are recorded in the PR and repository overnight audit. Evidence logs remain in `/tmp/trr-overnight-20261010-evidence`, including pipeline-fault-*, pipeline-restored-*, pipeline-candidate-ci.log and master-after-pipeline-ci.log. Passing totals supplement the boundary assertions and fault results.
