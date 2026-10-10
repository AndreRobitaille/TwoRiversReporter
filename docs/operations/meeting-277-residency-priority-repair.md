# Meeting 277 residency-policy and image repair

Prepared October 3, 2026 for [issue 157](https://github.com/AndreRobitaille/TwoRiversReporter/issues/157).
Andre authorized commit, push, issue closure, deployment, and the scoped repair
on October 3. The evidence below records the inspection before release;
deployment and repair results are recorded on the issue.

## Confirmed live evidence

- Running image: `24fb1271f17e58c319179dcc7801753efdc09e3b`.
- Meeting 277: City Council, October 5, 2026, 6 p.m.; still upcoming.
- Agenda item 3912: proposed ordinance 26-176 replaces the citywide residency
  prohibition with a 1,000-foot protected-location restriction. This is a
  citywide law change, not the disposition of an individual appeal.
- Extraction run 16231 correctly returned the tag `sex offender residency
  restrictions`, `topic_worthy: true`, and confidence 0.98.
- Topic 387 and blacklist entry 94 suppress that tag. Review event 248 blocked
  the topic on February 17, 2026, as "routine/generic/low resident salience"
  after earlier individual-appeal topics were merged into it.
- Summary 367 (`agenda_preview`) marks the ordinance highlight `high` and
  forestry `medium`, but its headline leads with the forestry application.
- Image 257 uses summary 367; its brief combines both issues into residential
  sidewalks and mature trees. It is ready, automatic, and used for feature/OG.
- Image source fingerprint:
  `0d4c47b83f1ab015163321e12000140a4c18a1cdb8b9db0ae57fbff13a53073c`.

## Rating-system audit

The shared AI score writer previously stored the last score received, regardless
of whether it came from an older individual appeal. The 0-10 `importance`
field does not affect the homepage: placement uses `resident_impact_score`
(1-5), with top stories at 4+ and the wire at 2+. Upcoming headline/interim
briefing updates previously did not establish a rating. A `status_update`
classification could also detach all topic appearances and block the topic.

`Topics::ResidentImpactPolicy` now applies a minimum of 3 for sex-offender
topics, 4 for source-title-supported law rewrites, and 5 for explicit replacement
of the citywide prohibition. The 4/5 minimum uses substantive, non-cancelled
agenda evidence newer than 30 days or from an upcoming meeting. Individual
relief requests, unrelated ordinances, and historical legislation cannot
establish that higher minimum. Topic row locks ensure stale AI jobs respect
current admin overrides. Headline/interim updates can establish a missing
priority before a full AI briefing, and low-activity pruning retains these
substantive appearances. Existing blocked records still require the bounded
repair below; the new policy does not automatically unblock them.

## Prepared replacement

The [official packet](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Packet-4e30dcfdf4c24c09833868015016035d.pdf#page=35)
contains the City map on physical page 35, labelled "1000' RADIUS FROM PROPERTY
LINES", with separate protected-location categories. Describe it as the map
included with the proposal, not as proof of an already-adopted ordinance.

The full page was rendered with Poppler and visually inspected. Its legend,
boundaries, scale, and City title remain intact. The local prepared PNG is
`tmp/residency-priority/meeting-277-official-map.png` (ignored; not a production
data copy). Recreate it from the public packet if the local artifact is absent.

```sh
pdftoppm -f 35 -singlefile -scale-to 2200 -png PACKET.pdf meeting-277-official-map
```

Packet SHA-256:
`d1c0321d69676d2f40fc79b43f4c34d869b44eea5cfdda529ffde34333695e2f`.
PNG SHA-256:
`54de1371909cf6acb023b8ddd60e3d0d3df0ea75fda17c99b65efb0a6699f9b8`.

## Authorized release and bounded repair

Apply only after explicit authorization to deploy and repair these records.
Establish and verify the single tunnel in the production playbook, inspect the
then-running revision and record state, and stop if any listed identities,
source fingerprint, or proposed policy scope changed. Preserve before-values
on the server for rollback; do not export the production database.

1. Deploy the verified code. Verify its exact running revision.
2. Selectively synchronize only the six changed prompts using
   `prompt_templates:sync_selected`: `generated_image_brief`, `extract_topics`,
   `triage_topics`, `analyze_topic_summary`, `analyze_topic_briefing`, and
   `analyze_meeting_content`. Review current/target hashes, apply with
   `EXPECTED_SHA256S`, rerun the dry run, and validate. Do not populate all
   production prompts.
3. In one guarded transaction, remove blacklist entry 94 only if its name
   still matches topic 387. Approve topic 387 with `review_status: approved`,
   `reuse_strategy: canonical`, impact 5, and this factual description:
   "City rules governing where covered sex offenders may live, including
   changes to those rules and individual residency appeals."
   Record the unblocking and its reason in `TopicReviewEvent`.
4. Link only agenda item 3912 to topic 387 with
   `AgendaItemTopic.find_or_create_by!`. This callback creates the appearance
   and queues continuity and a future-meeting briefing. Those follow-ups must
   run with the newly synchronized prompts. Do not reclassify unrelated items
   or run an all-meeting extraction/backfill.
5. Update only summary 367's headline to the source-supported lead:
   "Council will consider replacing its citywide sex-offender residency ban
   with a 1,000-foot restriction around protected locations on October 5."
   Retain highlights, item details, citations, source catalog, and preview
   framing. Advance the meeting timestamp for update discovery. Do not create
   motions, votes, or a claim of adoption.
6. Through the existing admin-upload workflow for meeting 277, upload the
   prepared map as an `admin_upload` override for `feature_and_og`. Retain
   image 257 as superseded. The upload must use the new full-source variants
   and "Uploaded image" cutline. Do not regenerate the neighborhood image.
7. Verify topic 387 is linked, visible, and prioritized; the briefing clearly
   distinguishes upcoming citywide legislation from earlier individual cases.
   Verify the corrected meeting headline, full map/legend, upload cutline,
   source packet link, OG image, and unchanged official records/citations.
   Check health and recent logs, then close the tunnel and remove temporary
   configuration. After a failed remote command, follow the five-minute
   cooldown rule before any single further attempt.

For rollback, restore the preserved topic, blacklist, summary headline, and
image state; remove only the new item-3912 association and generated follow-up
records identified by the repair snapshot. Keep official documents unchanged.
Code and database-backed prompt rollback require separate matching revisions.

## Local verification

- `PARALLEL_WORKERS=1 bin/rails test` for the generated-image helper, meeting
  and topic controllers, visual-brief builder, image generator, topic triage,
  AI prompt-template service, and prompt-template data: 121 tests, 519
  assertions, no failures/errors/skips. AI calls were mocked; no paid AI
  generation was used. Real libvips variant processing proved the top and
  bottom source-image edges survive uploaded-image resizing.
- Deliberately removing the triage protection caused the approved-topic
  assertion to fail with `blocked`. Restoring it passed the targeted test.
- Rating and pipeline coverage for the resident-impact policy, topic model,
  triage, headline/interim updates, appearance cleanup, all three AI scoring
  paths, homepage selector, and home controller: 144 tests, 459 assertions,
  no failures/errors/skips. This covers a current citywide proposal surviving
  an older individual-appeal score and reaching the homepage story pool.
- Deliberately removing the scoring minimum caused the current proposal to
  fall from 5 to 1; removing the cleanup protection deleted its appearance.
  Both tests failed as expected, and the protections were restored.
- `bin/rubocop`: all 573 Ruby files clean. `bin/rails zeitwerk:check` passed.
- `bin/rails prompt_templates:validate`: all 20 templates present with real
  content. Production database-backed prompts were not synchronized.
- `git diff --check` passed. Tests/lint used a temporary `BUNDLE_PATH` because
  four locked gems were absent from the machine's default bundle.
- The full public packet map was rendered and visually inspected. No official
  source data or map geography was altered.
- Inspection shell cleanup removed its temporary directory/control socket;
  local port 22222 was confirmed closed. No production writes were performed.
