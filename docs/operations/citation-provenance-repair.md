# Citation provenance and bounded repair

Implemented locally on October 2, 2026, from clean baseline
`330c4ffcb1d722f015b19535b2818d38e106b4e3`. No production inspection,
deployment, prompt synchronization, or record repair was performed. Tracked in GitHub Issues: #142 (https://github.com/AndreRobitaille/TwoRiversReporter/issues/142).

## Stored contract

`MeetingSummary.generation_data.source_catalog` snapshots only the documents
actually supplied to that analysis. Each source contains its meeting/document
IDs, document type, source URL, extracted-text SHA-256, artifact SHA-256 when
available, attachment checksum when present, physical page count, and hashes of
supported page extractions. `source_version` fingerprints that snapshot. It is
independent of the ten-run `PromptRun` retention limit and does not change merely
because an unrelated document was ingested or a metadata timestamp was touched.
The recorded prompt includes the same catalog and all supplied source text.

Each highlight, public-input entry, and item detail has structured `citations`:

```json
{"source_id":"doc-904","location":{"kind":"whole_source"}}
```

A PDF with actual page extractions can instead use
`{"kind":"pdf_page","page_number":2}`. A page count or a printed page label
alone does not ground a location. Unsupported, duplicate, or out-of-bounds
extractions cannot establish pages. Page extracts absent from the current full
text are treated as stale and cannot supply evidence or citation locations. If page extractions do not account for the
complete extracted text, the full text is preserved alongside the page extracts.
Transcripts have no supported pages or timestamps: ingestion discards caption
timing. Whole-source citations are honest and explicitly labelled.

Before saving, the server validates references against the supplied catalog and
current source version, then adds canonical document/version IDs, labels, and
citation identifiers. Invalid IDs, missing citations on reporting entries,
unsupported locations, and sources replaced during generation fail the run;
they do not overwrite the existing summary. Model URLs, labels, and additional
citation fields do not control links.

Minutes and supplemental transcripts stay separate in the catalog. A recording
citation supports recording evidence; it does not imply that approved minutes
record the same details. Topic contexts use the item's actual references rather
than selecting today's latest document by summary type. Topic summaries and
rolling briefings copy full validated references selected by citation ID and
retain source catalogs. Unresolved legacy references are not promoted to
validated topic evidence.

`Citations::Resolver` supplies both HTML and API citation presentation. A newer
document does not redirect citations away from the retained original document.
An in-place change to text, supported page extractions, document URL/type,
artifact digest, or attachment checksum makes the original reference unresolved.
Legacy labels such as `Page 1` remain visible as unresolved text without a link.
The website has no automatic minutes/packet PDF fallback.

The API preserves `label`, `document_id`, `source_url`, and `page_number`, adding
`status`, `reason` for unresolved references, and validated source/version,
location, and citation IDs for resolved references. PDF links include `#page=N`;
recording references link to the recording URL. Raw catalogs, extracted text,
private analysis fields, prompt inputs, and repair metadata are not returned in
citation payloads. Existing named-key authentication, eligibility, pagination,
privacy, and read-only boundaries are unchanged. HTML citations remain behind
the generated-content gate.

## Local WPPI evidence

The local retained records were rechecked, without production access:

- Meeting 268: City Council Work Session, September 28, 2026.
- Summary 357: `transcript_recap`, `source_type: transcript`.
- Transcript document 904: <https://www.youtube.com/watch?v=D5IjqSjiB1Y>.
- Retained analysis PromptRun 16143: all **100,871 characters** match document
  904's extracted text exactly. Its reporting matches summary 357.
- Input SHA-256:
  `dee791654d6fcc3b506deb07d9adcaffa00bb625a8c119af4cbd75376bce5eef`.
- Local dry run proposes changes to three highlight citations and two item
  citation entries, including WPPI agenda item 3787. Each becomes a whole
  recording/transcript reference. It applies no changes.

This is local evidence, not proof that the retained run is still available in
production. Recheck the live records inside the deployed image before repair.
No structured motion/vote records should be added for September 28: the current
minutes-based extraction policy still applies. Missing official decisions on
topic 969 are outside this citation repair.

## Repair command and safeguards

`citations:repair_summary` defaults to dry run and requires one explicit summary,
one retained analysis run, and one source document. It never calls AI or queues
follow-up jobs. It refuses another meeting/template, changed reporting,
truncated or missing retained input, a source that no longer matches, duplicate
candidate source identities, and legacy combined-source attribution.

The retained response must match all reporting/evidence fields after removing
only known citation fields and server metadata. Retained user messages must
contain the complete retained input. That input must uniquely match the selected
meeting document (or its complete, annotated page input). A PDF repair uses a
precise page only when its actual page extraction was supplied in the retained
input; otherwise it uses a whole-source reference. Combined-source legacy
summaries are deliberately refused because their old labels cannot establish
which document supported each claim. Other historical summaries require their
own provable retained input and individually selected IDs; there is no bulk scan
or automatic backfill.

The report contains the proposed citation changes, input digest, source version,
and a protected-record digest covering the narrative, evidence, summary source
and framing, legacy content, meeting, agenda items, documents, extractions,
motions, and votes. Apply runs in a transaction and checks that digest again.
Only citation fields/catalog/repair provenance and the summary's `updated_at`
change. Clients using `updated_since` can discover the correction. An identical
rerun changes nothing, including the timestamp.

Local dry run:

```sh
SUMMARY_ID=357 PROMPT_RUN_ID=16143 DOCUMENT_ID=904 bin/rails citations:repair_summary
```

Apply additionally requires `APPLY=true` and all three SHA-256 values from the
reviewed dry-run report as `EXPECTED_INPUT_SHA256`, `EXPECTED_SOURCE_VERSION`,
and `EXPECTED_PROTECTED_SHA256`. A changed proof refuses the write. Production
values must come from the production dry run, not this local database.

## Release order — requires Andre's explicit authorization

1. Read `.claude/skills/deploying/SKILL.md` and `config/deploy.yml`. Establish and
   verify the one persistent SSH tunnel before any production operation, even
   read-only inspection. Configure Kamal and Docker/buildx to use it; use
   `trr_kamal` for every Kamal command. Keep that shell/tunnel through final
   verification. No direct or parallel SSH fallback; stop if the tunnel fails.
2. Commit/push the reviewed change when authorized, then deploy it first with
   `trr_kamal deploy`. There is no schema migration for this change. Verify the
   exact running image revision before executing the new tasks. Existing stored
   legacy citations will display as unresolved until individually repaired.
3. Selectively synchronize **only** `analyze_meeting_content`,
   `analyze_topic_summary`, and `analyze_topic_briefing`, from the newly running
   image. Do not populate every production prompt or run AI regeneration.

   ```sh
   trr_kamal app exec 'env KEYS=analyze_meeting_content,analyze_topic_summary,analyze_topic_briefing bin/rails prompt_templates:sync_selected'
   ```

   Review each `current`/`target` fingerprint. Apply with `APPLY=true` and
   `EXPECTED_SHA256S=analyze_meeting_content=CURRENT_SHA,analyze_topic_summary=CURRENT_SHA,analyze_topic_briefing=CURRENT_SHA`.
   Use `env` inside the remote command. Run the dry run again and verify all
   three fingerprints are unchanged; run `prompt_templates:validate`.
4. Recheck live summary/source/run identity with the bounded dry run:

   ```sh
   trr_kamal app exec 'env SUMMARY_ID=357 PROMPT_RUN_ID=16143 DOCUMENT_ID=904 bin/rails citations:repair_summary'
   ```

   Confirm the exact full-input SHA above, the actual recording URL and source
   type, the five citation-only changes, and narrative/evidence preservation.
   If run 16143 has been pruned or differs, stop. Local evidence does not justify
   importing a fabricated PromptRun or guessing another source. A separately
   approved archival-evidence workflow would be needed.
5. Before applying, preserve an on-server snapshot of summary 357's original
   `generation_data`, `content`, and timestamp in a protected operator file.
   Keep official source/motion/vote hashes and the dry-run proof. Do not copy
   production reporting/database data to the workstation without separate
   authorization. Take the playbook's dump if any separately approved operation
   introduces a destructive migration; this change has none.
6. Execute the explicitly authorized, fingerprint-guarded repair:

   ```sh
   trr_kamal app exec 'env SUMMARY_ID=357 PROMPT_RUN_ID=16143 DOCUMENT_ID=904 APPLY=true EXPECTED_INPUT_SHA256=INPUT_SHA EXPECTED_SOURCE_VERSION=SOURCE_SHA EXPECTED_PROTECTED_SHA256=PROTECTED_SHA bin/rails citations:repair_summary'
   ```

   Replace the three placeholders with the reviewed production dry-run values.
   Save the report; `applied` must be true and protected hashes must match.
   Rerun with the same values and verify `changed: false`, `applied: false`,
   and an unchanged repaired timestamp. No topic/reporting regeneration belongs
   in this procedure. Repair any other summary only after a separate evidence
   review and bounded selection.
7. Verify `/meetings/268` citation links as an authorized resident and API
   summary/agenda-item citation payloads with an existing owner-approved named
   key. Do not provision or expose credentials. Confirm the WPPI item points
   to document 904's recording, `page_number` is null, location is whole source,
   and all reporting, decisions, vote/evidence fields, and official records
   match the pre-repair snapshot. Query `updated_since` with the pre-repair
   timestamp and confirm meeting 268 is discovered. Check anonymous gating,
   unauthorized API responses, and unchanged official motion counts.
8. Verify the exact image, recent logs, and public health/sign-in/admin routes
   as specified in the playbook. Keep the tunnel for these checks, then exit
   its persistent shell and verify temporary configuration/socket removal and
   closure of port 22222. After a failed remote command, wait at least five
   minutes before a single further attempt; do not loop.

For reversal, use the preserved on-server summary snapshot to restore only its
original citation-bearing JSON/content after verifying reporting and official
hashes still match. Advance `updated_at` on that restoration so clients discover
it. Do not recreate source documents, motions, or votes or rerun analysis.
Code rollback and database prompt rollback are separate: an older image must
have its compatible prior prompt versions restored before future analysis runs.

## Verification record

Completed local checks on October 2, 2026:

- Targeted Minitest: **200 tests / 1,463 assertions**, zero failures/errors/skips.
  Command: `PARALLEL_WORKERS=1 bin/rails test` with
  `test/services/citations`, `test/helpers/meetings_helper_test.rb`,
  `test/controllers/meeting_citations_test.rb`,
  `test/controllers/api/resident_api_test.rb`,
  `test/jobs/summarize_meeting_job_test.rb`,
  `test/jobs/topics/generate_topic_briefing_job_test.rb`,
  `test/services/topics/summary_context_builder_test.rb`,
  `test/services/topics/recent_item_details_builder_test.rb`,
  `test/services/ai/open_ai_service_analyze_meeting_test.rb`,
  `test/lib/prompt_template_data_test.rb`, and
  `test/tasks/prompt_templates_rake_test.rb`.
- `PARALLEL_WORKERS=1 GEM_SPEC_CACHE=/tmp/trr-gem-spec-cache RUBOCOP_CACHE_ROOT=/tmp/trr-rubocop-cache bin/ci`:
  **1,927 tests / 9,022 assertions**, zero failures/errors, one skip;
  `bin/rubocop` passed all 570 Ruby files; bundler-audit and importmap audit
  passed; Brakeman reported zero warnings.
- `bin/rails prompt_templates:validate`: all 20 templates present with real
  content. Only the three changed templates were selectively synchronized in
  the local development database, with fingerprint guards and an unchanged
  follow-up dry run. Production prompts were not touched.
- `bin/rails zeitwerk:check` and `git diff --check` passed.
- Separate deliberate removals of the HTML citation-helper gate and the API
  citation projection each caused the intended assertion failure after their
  protected tests passed. Both protections were restored before final CI.
- `SUMMARY_ID=357 PROMPT_RUN_ID=16143 DOCUMENT_ID=904 bin/rails citations:repair_summary`
  produced the five-entry local WPPI dry run. A local transaction then exercised
  apply and rerun, confirming preserved narrative/evidence/official hashes,
  recording links in both API projections, matching topic/briefing provenance,
  and timestamp advancement. That transaction was rolled back, and the full
  original summary attributes were verified restored. No WPPI AI reporting was
  regenerated and no production access occurred.

Local evidence logs are under `tmp/citation-provenance-validation/` (gitignored):
`targeted-final.log`, `ci-final.log`, the two protection-removal log pairs, and
`wppi-preservation.json`. No paid AI calls were made for these checks.

Tests cover transcript-only, PDF-only, combined sources, a recap with an
unrelated packet PDF, invalid/cross-meeting IDs, invented pages/timestamps,
legacy ambiguity, source replacement, provenance through topic/briefing context,
HTML/API agreement and whitelists, anonymous gating, citation-only preservation,
updated_since discovery, dry-run proof guards, and idempotency.
