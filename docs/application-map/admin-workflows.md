# Administrative workflows

All entries are **documented, runtime unverified**. Each starts with an active
administrator, at least one owned passkey, and the tolerant admin context gate.
Strict context and a fresh 15-minute proof additionally apply to account create,
delete, admin-role/disable changes, and application deletion. Do not infer that
every destructive admin action has this extra gate; the route inventory shows
dispatch, and individual controllers define enforcement.

Requirements: [development plan](../DEVELOPMENT_PLAN.md),
[admin design and shipped corrections](../superpowers/specs/2026-07-26-admin-ui-revamp-design.md),
[passwordless design](../superpowers/specs/2026-07-23-passwordless-auth-and-applications-design.md),
[session design](../superpowers/specs/2026-07-25-session-and-reauthentication-hardening-design.md),
[Topic Governance](../topics/TOPIC_GOVERNANCE.md),
[triage design](../plans/topic-triage-tool.md),
[prompt management](../plans/2026-03-28-prompt-management-design.md),
[prompt evaluation](../plans/2026-03-29-prompt-editor-test-run-design.md),
[transcript import](../superpowers/specs/2026-06-30-admin-transcript-import-design.md),
[SRT upload](../superpowers/specs/2026-07-07-admin-transcript-srt-upload-design.md),
[meeting image management](../superpowers/specs/2026-06-14-admin-meeting-image-management-design.md),
and [generated images](../superpowers/specs/2026-06-14-generated-civic-images-design.md).
For CRUD interactions without a more specific approved requirement, error/reload
assertions below are candidate acceptance criteria based on the user's brief.

## ADM-01 — Enter Admin and navigate between tools (P1)

- **Start / data:** eligible admin; compare anonymous/member/admin-without-passkey
  and unfamiliar/stale-context sessions.
- **Action:** public Admin link → launcher/sidebar entry; open/close mobile drawer;
  visit contextual record tools, Security or Public Site.
- **Required state / visible outcome:** intended tool opens with coherent navigation;
  anonymous gets sign-in, member is denied, no-passkey admin gets setup, unfamiliar
  context gets AUTH-12. Reading does not grant additional authority.
- **Next:** direct URLs obey the same boundary; mobile navigation and Sign Out
  remain usable. Missing admin record redirects with a notice rather than pretending it exists.
- **Failure variants:** hidden/unavailable tool, drawer/overlay trap, challenge loop,
  different launcher/sidebar destinations, leaked admin data before denial.
- **Observed:** [BaseController](../../app/controllers/admin/base_controller.rb),
  [Navigation](../../app/models/admin/navigation.rb),
  [admin layout](../../app/views/layouts/admin.html.erb),
  [sidebar controller](../../app/javascript/controllers/admin_sidebar_controller.js).

## ADM-02 — Review, approve or deny membership (P1)

- **Start / data:** pending account with email-pending/submitted application;
  decision reason, historical records, and another administrator reviewing concurrently.
- **Action:** User Accounts → account → read details → approve or deny with reason.
- **Required state / visible outcome:** decision saves account/application status,
  reviewer/time/reason and sends the corresponding notification. Approval makes
  AUTH-08 possible; denial blocks sign-in/reapplication and emails the exact reason.
- **Next:** reload history/groups reflect decision; missing reason is usable error,
  not a false success; no-reviewable-application/concurrent decision fails coherently.
- **Failure variants:** provider failure with compensating state restoration,
  raced review, historic application selected incorrectly, applicant still mid-form.
- **Observed:** [UsersController](../../app/controllers/admin/users_controller.rb),
  [decision service](../../app/services/admin/membership_application_decision.rb).
  The service's compensation does not prove the browser avoids a 500 on delivery failure.

## ADM-03 — Delete an account or a single application (P0)

- **Start / data:** target account/application with sessions, keys, credentials,
  own applications and references to other records; fresh strict-context administrator.
- **Action:** confirm Delete account permanently or delete a single application.
- **Required state / visible outcome:** chosen deletion succeeds atomically with
  audit; account deletion removes its authentication/application records while
  surviving unrelated referenced content/reviewer history. Single application
  deletion leaves its account and account eligibility intact.
- **Next:** old cookies/keys fail after account deletion; referenced images,
  other applicants' records and audit snapshots remain readable. Refused deletion
  does not create a successful-deletion audit event.
- **Failure variants:** self-deletion, last usable administrator, stale proof/context,
  missing record, foreign-key references, concurrent last-admin changes.
- **Observed:** [UsersController#destroy](../../app/controllers/admin/users_controller.rb),
  [application deletion](../../app/controllers/admin/membership_applications_controller.rb),
  [User associations/guards](../../app/models/user.rb), [AuditEvent](../../app/models/audit_event.rb).

## ADM-04 — Change account eligibility, role or sessions (P0)

- **Start / data:** active/disabled/pending/rejected targets, multiple sessions and
  valid keys; current admin and last usable admin controls; fresh strict-context proof for role/disable.
- **Action:** Make/Remove admin, Disable/Re-enable, revoke one session or all sessions.
- **Required state / visible outcome:** targeted authority persists and is audited;
  self-lockout/last-usable-admin removal is refused. Re-enable applies only to active
  disabled accounts; pending/rejected status is not silently approved.
- **Next:** target's next request reflects actual authority (AUTH-05/15); revoked
  cookies remain invalid. Session revocation is not API-key revocation; role grant
  still requires target passkey before Admin works.
- **Failure variants:** foreign session ID, stale privilege cache, concurrent admin
  removal, false re-enable success, changed-context mutation.
- **Observed:** [UsersController](../../app/controllers/admin/users_controller.rb),
  [User](../../app/models/user.rb), [API-key contract](../read-only-api.md).

## ADM-05 — Create another administrator and inspect account metadata (P0)

- **Start / data:** fresh strict-context admin; deliverable unique address;
  accounts with/without applications, sessions, passkeys and API keys.
- **Action:** User Accounts → New → create; inspect account detail/session/key metadata.
- **Required state / visible outcome:** active admin account is created/audited;
  invalid/duplicate email gives correctable error. No other person's passkey or
  full API secret is recoverable/editable from this screen.
- **Next:** new admin must complete ordinary sign-in and own passkey setup;
  account creation is not an implicit first usable administrator or automatic email delivery.
- **Failure variants:** invalid form, stale proof/context, confusing civic Members
  with website accounts, accidental key-secret/digest exposure.
- **Observed:** [UsersController#create/show](../../app/controllers/admin/users_controller.rb),
  [user views](../../app/views/admin/users/show.html.erb).

## ADM-06 — Review and edit a topic in the inbox/detail workspace (P1)

- **Start / data:** topics across review/lifecycle/pinned states, evidence and
  aliases, impact override, generated/admin description; failed validation variant.
- **Action:** filter/sort → expand lazy evidence → detail; edit canonical name,
  description, context, importance (0–10), resident impact (1–5); approve/block/
  unblock/review/pin/unpin using exposed controls.
- **Required state / visible outcome:** persistent edit/state matches intent;
  inline validation is visible; row replacement/removal agrees with current filter.
  Manual descriptions remain protected; impact affects resident ranking separately
  from importance. Review transitions retain evidence and review accountability.
- **Next:** reload/query/public visibility confirms result; blocking adds persistent
  blocklist entry; unblocking does not remove it. Description generation is background work.
- **Failure variants:** blank/duplicate name, stale UI, silent Turbo failure,
  omitted reason/history, context-save failure (V-10). Bulk update is preserved
  without a current selection UI, not a normal inbox journey (V-06).
- **Observed:** [TopicsController](../../app/controllers/admin/topics_controller.rb),
  [workspace view](../../app/views/admin/topics/show.html.erb),
  [inbox query](../../app/services/admin/topics/inbox_query.rb).

## ADM-07 — Combine duplicates or retire a topic (P0)

- **Start / data:** two distinct topics with aliases, overlapping/distinct agenda
  links, appearances, summaries, knowledge context and a rolling briefing; reason.
- **Action:** candidate search → inspect impact/evidence → confirm combine/merge-away/
  topic-to-alias; or review retirement consequences → block with reason.
- **Required state / visible outcome:** intended surviving identity and coherent
  civic continuity; affected counts/consequences are reviewable before submission.
  Retirement blocks public visibility/reuse and adds blocklist; it does not erase
  official source records. Merge records destination review and retires the duplicate URL.
- **Next:** old source topic GET/HEAD resolves to survivor; search/associations use
  correct canonical identity; reload verifies surviving distinct events and deduplication.
- **Failure variants:** self-merge, wrong direction, nonexistent target, alias
  collision, absent required reason, partial relationship movement. Conflicting
  summary/briefing handling is a review point, not a promise of byte-for-byte preservation.
- **Observed:** [TopicRepairsController](../../app/controllers/admin/topic_repairs_controller.rb),
  [MergeService](../../app/services/topics/merge_service.rb),
  [impact preview](../../app/services/admin/topics/impact_preview_query.rb),
  [redirect middleware](../../lib/middleware/redirect_middleware.rb).

## ADM-08 — Correct topic aliases and canonical identity (P1)

- **Start / data:** aliases belonging to the chosen topic, other possible owners,
  zero/one/multiple aliases, normalization collisions and glued legacy names.
- **Action:** keep (no mutation), rename, remove, move to another topic, promote
  standalone, or flip canonical name with its sole alias; inspect confirmation/impact.
- **Required state / visible outcome:** intended lookup ownership/name persists;
  promotion creates a proposed topic for further review; another owner's alias
  cannot be mutated by selecting its ID under this topic. Glued legacy aliases
  cannot become overriding canonical topics/names.
- **Next:** normalized lookup and resident/admin search recover intended identity;
  alias removal affects lookup but does not erase its topic's official history.
- **Failure variants:** alias disappeared, wrong topic, target missing, collision,
  invalid promotion/flip, interrupted modal/select flow.
- **Observed:** [repair controller](../../app/controllers/admin/topic_repairs_controller.rb),
  [alias rail](../../app/views/admin/topics/_alias_repair_rail.html.erb),
  [flip](../../app/services/topics/flip_alias_service.rb),
  [promotion](../../app/services/topics/promote_alias_service.rb).

## ADM-09 — Maintain the extraction blocklist (P1)

- **Start / data:** normalized prohibited topic name/reason and existing entry;
  topic may independently be approved, proposed or blocked.
- **Action:** Blocklist → add or remove an entry; confirm actual lookup after reload.
- **Required state / visible outcome:** extraction blacklist changes independently
  from an existing topic's review/visibility status; failure does not silently succeed.
- **Next:** future extraction/triage honors current entry; removing it does not
  automatically approve an already blocked topic. Governance-required substantive
  concerns need reviewed repairs, not an implicit automatic unblock.
- **Failure variants:** duplicate/blank/normalized name, wrong delete ID, confusion
  with topic block/unblock. Routed extra REST actions are absent (V-02).
- **Observed:** [TopicBlocklistsController](../../app/controllers/admin/topic_blocklists_controller.rb),
  [TopicBlocklist](../../app/models/topic_blocklist.rb), [Topic Governance](../topics/TOPIC_GOVERNANCE.md).

## ADM-10 — Maintain committees and civic-person identity (P1)

- **Start / data:** committee with meetings/memberships/aliases; civic Member with
  aliases, attendance/votes/current offices and another merge candidate.
- **Action:** committee create/edit/delete or alias add/remove; civic member
  inspect/alias add/remove/merge into target.
- **Required state / visible outcome:** valid fields persist, invalid forms remain
  correctable; aliases resolve correct body/person; descriptions inform future AI
  context. Merging a person preserves coherent votes/attendance/membership identity.
- **Next:** public directory/profile links reflect names/status and source-backed
  roles. Committee deletion nullifies meeting association rather than deleting meetings.
- **Failure variants:** duplicate name/slug/alias, self-merge, lost historical
  associations, changed committee slug breaking old link. Canonical roster sync
  and direct current-membership editing are not exposed controls on this interface.
- **Observed:** [CommitteesController](../../app/controllers/admin/committees_controller.rb),
  [MembersController](../../app/controllers/admin/members_controller.rb),
  [Committee](../../app/models/committee.rb), [Member](../../app/models/member.rb).

## ADM-11 — Add or curate knowledge context (P1)

- **Start / data:** manual note/PDF or extracted/pattern source with status,
  verification notes/date, active flag and associated chunks/topic links.
- **Action:** Knowledge Sources → create/edit/approve/block/deactivate/delete;
  request re-ingest; inspect details after worker completion.
- **Required state / visible outcome:** valid source persists; content change or
  explicit re-ingest queues correct work; approved/active context participates in
  retrieval according to governance and stays labeled separately from official record.
- **Next:** retrieve distinctive content after completion; deletion removes source
  chunks/links and future retrieval cannot use them. Hand-editing generated body
  changes its origin to manual in the current implementation.
- **Failure variants:** invalid source/status, missing file/title, failed extraction/
  embedding, stale chunks after edit, unapproved context affecting reporting.
- **Observed:** [KnowledgeSourcesController](../../app/controllers/admin/knowledge_sources_controller.rb),
  [KnowledgeSource](../../app/models/knowledge_source.rb),
  [ingestion job](../../app/jobs/ingest_knowledge_source_job.rb), [RetrievalService](../../app/services/retrieval_service.rb).

## ADM-12 — Search knowledge and optionally ask AI (P1)

- **Start / data:** searchable chunks and official documents with distinguishable
  origins; blank/no-match query; explicit authorization for any real AI evaluation.
- **Action:** Knowledge Search → query; optionally choose Ask AI when context exists.
- **Required state / visible outcome:** source-identifiable chunk/document results;
  AI answer is distinguishable from retrieved evidence and cites supplied numbered context.
- **Next:** follow source/meeting links and verify claims; ordinary search and
  optional answer have different costs/dependencies.
- **Failure variants:** embedding/provider outage, no chunks, unsupported answer,
  misleading origin label. A GET with `ask_ai` can invoke paid work: it is not a harmless QA probe.
- **Observed:** [SearchesController](../../app/controllers/admin/searches_controller.rb),
  [search view](../../app/views/admin/searches/index.html.erb),
  [AI service](../../app/services/ai/open_ai_service.rb).

## ADM-13 — Find a meeting and manage its illustration (P1)

- **Start / data:** meeting/topic and current ready, failed, disabled or missing
  image; eligible upload (PNG/JPEG/WebP up to 10 MB); known place/provenance context.
- **Action:** meeting/topic detail → upload replacement, queue generation with
  optional prompt, or disable selected image; return to parent.
- **Required state / visible outcome:** allowed image control persists; new
  ready upload supersedes previous ready images; queued generation is represented
  as queued/background work. Illustrations never claim to be factual source photos.
- **Next:** reload image panel/public page after completion; disabled/failed image
  is not displayed as current ready; correct parent remains the return destination.
- **Failure variants:** spoofed file type/oversize/invalid parent, provider failure,
  unsafe return path, wrong image ownership, absent local blobs. Broken local
  thumbnails alone are expected and do not establish a production regression.
- **Observed:** [GeneratedImagesController](../../app/controllers/admin/generated_images_controller.rb),
  [image panel](../../app/views/admin/generated_images/_panel.html.erb),
  [GeneratedImage](../../app/models/generated_image.rb),
  [Generator](../../app/services/generated_images/generator.rb). Real generation requires separate authorization.

## ADM-14 — Check/import a transcript and follow completion (P1)

- **Start / data:** existing meeting, valid YouTube watch URL; caption source or
  uploaded nonempty `.srt`; separately existing transcript, missing captions and blocked download.
- **Action:** filter/select meeting; Check URL; choose/remove optional SRT; Begin
  Import; refresh Recent workflows and inspect logs.
- **Required state / visible outcome:** URL precheck makes no import/reporting
  records. Begin Import creates queued workflow. Upload takes precedence over
  downloading but keeps recording URL. Worker logs running→completed/failed and
  ordered import, summary, pruning and topic reanalysis stages.
- **Next:** compare source text→recap details→topic associations/briefings (BG-03/04),
  preserving distinct content and official proposal evidence. Completed status alone
  cannot prove useful content. Failure logs identify stage; no dedicated per-import retry button exists.
- **Failure variants:** invalid meeting/URL/SRT, no captions, provider/AI failure,
  partial completed upstream stages, imported transcript reuse/replacement, stale form selection.
- **Observed:** [TranscriptImportsController](../../app/controllers/admin/transcript_imports_controller.rb),
  [view](../../app/views/admin/transcript_imports/show.html.erb),
  [workflow job](../../app/jobs/admin/transcript_import_workflow_job.rb),
  [TranscriptImport](../../app/models/transcript_import.rb). Check URL makes an external metadata request.

## ADM-15 — Regenerate a meeting recap (P1)

- **Start / data:** one meeting or bulk meetings with summarizable minutes/packet
  text; known expected source tier; worker and required prompt templates.
- **Action:** Summaries → regenerate one/all → inspect queue and resulting meeting.
- **Required state / visible outcome:** request queues intended targets; generated
  output obeys evidence/provenance contracts; original records remain intact.
  Coverage counters or queue notice are not proof that every job succeeded.
- **Next:** read updated detail/citations/API freshness and compare important
  source content; reruns are idempotent and do not duplicate topic appearances/votes.
- **Failure variants:** absent source/prompt, AI failure/context overflow,
  lower-tier source replacing higher-tier recap, incorrect bulk count, worker unavailable.
- **Observed:** [SummariesController](../../app/controllers/admin/summaries_controller.rb)
  bulk selection requires minutes/packet extracted text; [SummarizeMeetingJob](../../app/jobs/summarize_meeting_job.rb).
  Other transcript/agenda enrichment paths are BG-02/03, not this bulk filter.

## ADM-16 — Preview targets and enqueue a supported job (P1)

- **Start / data:** allowed job type; meeting date/body filters, topic IDs or no-target
  job; topic briefing needs a latest linked meeting.
- **Action:** Run a Job → choose type/targets → preview count → enqueue.
- **Required state / visible outcome:** intended type/targets queued once per
  applicable target, with clear confirmation; unknown type is rejected. Count and
  eventual effects must agree for eligible targets (candidate acceptance).
- **Next:** inspect Queue & Failures and actual downstream records; force-image
  and AI jobs can have cost even if described as a rerun.
- **Failure variants:** invalid filters/empty selection, preview drift, deleted
  target, topic lacking meeting, missing workers. Some no-op/skipped targets need
  observation; an enqueue notice does not promise published content.
- **Observed:** [JobRunsController](../../app/controllers/admin/job_runs_controller.rb)
  allowlist: topics/votes/members/meeting recap/images, topic briefing/description/
  images, triage and full scrape. No arbitrary class/command entry.

## ADM-17 — Inspect failures, retry or clear queue history (P1)

- **Start / data:** ready/scheduled/claimed/failed/completed jobs, stale/live workers;
  a failed idempotent job with known expected downstream outcome.
- **Action:** Queue & Failures → inspect error → retry one/all, discard one, or
  Clear All Finished; exercise any displayed confirmation.
- **Required state / visible outcome:** retried work becomes ready and later
  produces intended result without duplicate effects; discard removes selected
  failed work; clear history affects exactly the announced categories.
- **Next:** worker heartbeat and job completion are separate evidence; failure
  removal alone is not recovery. Transcript workflow failures may live only in
  TranscriptImport because its job records and catches errors.
- **Failure variants:** double retry, missing worker, partially failed operation,
  accidental clearing, completion without correct content. **Clear All Finished
  currently removes failed jobs as well as completed jobs**, not just success history.
- **Observed:** [JobsController](../../app/controllers/admin/jobs_controller.rb),
  [queue view](../../app/views/admin/jobs/show.html.erb),
  [ApplicationJob](../../app/jobs/application_job.rb). Confirmation behavior needs browser validation.

## ADM-18 — Edit/version a prompt and evaluate a retained example (P1)

- **Start / data:** existing template, versions and retained PromptRun; valid
  placeholders/model tier; deliberate approval for a real evaluation.
- **Action:** Prompts → edit system role/instructions/tier/note → save → version
  diff; choose example/model and Test Run.
- **Required state / visible outcome:** saved template/version is recoverable
  and future runs use it; comparison identifies original versus new output/error
  without overwriting the example's source reporting. Unsaved evaluation text is distinct from Save.
- **Next:** reload verifies saved fields/diff; downstream work uses deployed
  database template, not an assumed hardcoded fallback. Test Run makes an AI call;
  no cost-incurring evaluation belongs in routine map maintenance.
- **Failure variants:** invalid fields, missing example/template, wrong template
  context, unavailable model/provider, comparison error, missing version, invalid-save page.
- **Observed:** [PromptTemplatesController](../../app/controllers/admin/prompt_templates_controller.rb),
  [PromptTemplate](../../app/models/prompt_template.rb),
  [PromptEvaluator](../../app/services/ai/prompt_evaluator.rb),
  [editor JavaScript](../../app/javascript/controllers/prompt_editor_controller.js).

## ADM-19 — Change public access mode or a URL redirect (P0)

- **Start / data:** current SiteSetting/default-open absence; redirect source and
  relative destination with supported 301/302/307/308 status; cached prior responses.
- **Action:** Access Mode → choose/save; or Redirects → create/edit/delete.
- **Required state / visible outcome:** mode applies next request with RES-11
  boundaries and audit; invalid mode does not persist. Valid redirect affects
  GET/HEAD source and correct destination; invalid/self/external destination rejected.
- **Next:** test anonymous/member/crawler representations and old URLs; delete
  invalidates redirect cache. Mode never changes Account/Admin eligibility.
- **Failure variants:** stale cache, withheld metadata, redirect loop/chain,
  mutation URL unexpectedly redirected, typo/unsupported code. Redirect `show` is absent (V-02).
- **Observed:** [SiteSettingsController](../../app/controllers/admin/site_settings_controller.rb),
  [RedirectsController](../../app/controllers/admin/redirects_controller.rb),
  [Redirect](../../app/models/redirect.rb), [middleware](../../lib/middleware/redirect_middleware.rb).

## ADM-20 — Review an audit event after a sensitive action (P1)

- **Start / data:** successful/refused deletion, privilege or account/application/
  access-mode/API-key change; deleted actor/subject variant.
- **Action:** perform selected workflow → Audit Log → inspect latest event.
- **Required state / visible outcome:** audited successful action has faithful
  actor/subject snapshots, time/context and allowed metadata; no raw credential
  or false-success deletion record. History survives actor deletion.
- **Next:** correlate displayed outcome with persisted state; older events can be
  outside the latest-200 list. TopicReviewEvent is a separate editorial trail.
- **Failure variants:** dangling actor, missing record, rejected mutation logged
  as successful, leaked secret/digest, assuming all admin edits are audited.
- **Observed:** [AuditEventsController](../../app/controllers/admin/audit_events_controller.rb),
  [AuditEvent](../../app/models/audit_event.rb),
  [audit view](../../app/views/admin/audit_events/index.html.erb).
