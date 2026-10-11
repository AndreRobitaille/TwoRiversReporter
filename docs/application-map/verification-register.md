# Discrepancies and verification needs

This register preserves the October 10 discovery findings. Subsequent verified
work and remaining decisions are recorded in [overnight progress](overnight-progress.md)
and [reviewed contracts](behavior-contracts.md). Browser foundation #169, resident-context defect #176, notification scheduling #174 and admin route/maintenance #170 are resolved in PRs #177/#178/#180/#181. Recovery #173 and passkey #175 have verified drafts #179/#182 with decisions still open; #171/#172 preserve unresolved policies. The prioritized #168 audit now also includes real offline transcript preservation/rerun proof in PR #186 (#183); broader variants remain explicitly unknown. The historical evidence below does not imply resolved findings remain untested.

This is a discovery register, not a completed defect or test-coverage audit.
**All items remain open** at the 2026-10-10 baseline. No passing test count, source
comment, route-presence check, or issue creation closes an item.

## GitHub follow-up

Nine issues were created after checking the repository's existing issues. Each
was re-fetched to verify its title, body, labels, and open state. Related findings
share scoped follow-ups; existing research-view and planned admin-interface work
remain in their original issues. No pre-existing issue was changed or closed.
Issue #168 was subsequently expanded to include an evidence-based review of test
and assertion simplification, with retained coverage and defect-detection checks.

| Finding | Behavioral-testing follow-up |
| --- | --- |
| V-01 / V-11 | [#168: Workflow test-effectiveness audit](https://github.com/AndreRobitaille/TwoRiversReporter/issues/168); [#169: Browser sign-in/logout and CI discovery](https://github.com/AndreRobitaille/TwoRiversReporter/issues/169) |
| V-02 / V-06 | [#170: Real admin navigation and missing dispatch targets](https://github.com/AndreRobitaille/TwoRiversReporter/issues/170); future controls remain in [#152](https://github.com/AndreRobitaille/TwoRiversReporter/issues/152) |
| V-03 / V-04 | [#171: Reconcile behavioral specifications](https://github.com/AndreRobitaille/TwoRiversReporter/issues/171); research implementation remains in [#62](https://github.com/AndreRobitaille/TwoRiversReporter/issues/62) |
| V-05 | [#172: Anonymous source links, rosters, and teasers](https://github.com/AndreRobitaille/TwoRiversReporter/issues/172); possessed blob-URL decision remains in [#154](https://github.com/AndreRobitaille/TwoRiversReporter/issues/154) |
| V-07 | [#173: Expired approval-link recovery](https://github.com/AndreRobitaille/TwoRiversReporter/issues/173) |
| V-08 | [#174: Eventual notifications across cooldown/failure](https://github.com/AndreRobitaille/TwoRiversReporter/issues/174) |
| V-09 | [#175: Passkey page/endpoint context alignment](https://github.com/AndreRobitaille/TwoRiversReporter/issues/175) |
| V-10 | [#176: Nonblank resident context and provenance](https://github.com/AndreRobitaille/TwoRiversReporter/issues/176) |

These issues specify outcome/state assertions, appropriate exercised boundaries,
runner evidence, and isolated fault experiments where applicable. Policy conflicts
are marked for decision; static defect candidates remain unconfirmed. Issue filing
did not run application tests, browser journeys, or production/provider operations.

## V-01 — Browser/runtime behavior is not demonstrated

**Observed:** requirements and source were mapped, but no browser task, real
provider delivery, production request, fixture-driven request suite or controlled
defect experiment was run. Current checkout's ordinary tests were not rerun.

**Implication:** all workflow execution/coverage/effectiveness statuses are
unknown. In particular, the user's logout example motivates AUTH-04 but does
not establish a currently reproduced logout 500 in this application.

**Next evidence:** validate high-priority complete journeys, first proving the
starting allowed state, and record environment/revision, actions, state/assertions
and subsequent requests. See [maintenance-and-qa.md](maintenance-and-qa.md).

## V-02 — Declared routes point to absent actions

**Observed:** local Rails route enumeration plus `action_methods` comparison
found these 10 dispatch rows without an action:

| Controller | Absent dispatches |
| --- | --- |
| `admin/topics` | POST create; GET new/edit; DELETE destroy |
| `admin/topic_blocklists` | GET new/edit/show; PATCH and PUT update |
| `admin/redirects` | GET show |

These are expanded by exact path in [routes.md](routes.md). They arise from
unrestricted `resources` declarations despite a narrower implemented interface.
`promote_alias` is also declared twice for the same target/path.

**Intended behavior:** only real, authorized user interfaces should be represented
as available workflows. Whether these routes should be removed or implemented
needs a scoped decision; a route declaration does not establish feature intent.

**Next evidence:** review actual links/helper use and route expectations, then
resolve declarations or implementation. No requests were dispatched and no
specific HTTP failure status is claimed by this map. ADM-06/09/19 are affected.

## V-03 — Explore Topics is a placeholder

**Observed:** [TopicsController#explore](../../app/controllers/topics_controller.rb)
has no discovery logic and [the page](../../app/views/topics/explore.html.erb)
states that the research view is coming soon, with a return link and `noindex`.

**Intended versus implemented:** promised historical/filter research is future
scope. Existing ordinary topic search and API research remain separate capabilities.

**Next evidence:** keep this explicitly unfinished until a feature contract and
usable controls ship; do not create tests that treat placeholder 200 as research success.

## V-04 — Older product/handbook descriptions disagree with current capabilities

**Observed disagreements:**

- [Audience](../AUDIENCE.md) says no accounts/no search; [repository README](../../README.md)
  still lists no public user accounts as a non-goal. Current binding development
  plan and specialized auth/API designs explicitly support approved accounts/search.
- Development plan's older Home layout uses What Happened/Coming Up cards and
  weekly meeting lists. Current [home selection](../../app/services/resident_content/home_selection.rb)
  and views use Top Stories/Wire/Next Up. Page playbook says some homepage links
  go to meetings, but current story/wire partials link to topics.
- Older topic/meeting layout descriptions promise all sections always visible.
  Current views adapt several sections to available data, with legacy recaps and
  gating branches; the topic playbook also describes adaptive sections.
- Older operational plan says discovery is unscheduled. [Recurring config](../../config/recurring.yml)
  now declares daily 11pm discovery. This proves configuration, not live execution.

**Resolution boundary:** newer specialized requirements govern their domain, but
where binding layout expectations conflict, observed code does not silently
become approved product intent. This map records the current interface and keeps
the conflicts visible without rewriting the historical specs.

**Next evidence:** review and reconcile the source documents for auth/search,
homepage navigation/layout, section/empty states, and operational scheduling.
RES-01/04/05/06/12 and BG-01 are affected.

## V-05 — Public-source and roster gating descriptions need reconciliation

**Required:** official records remain authoritative/public, and generated
analysis/aggregation is the layer the gate protects. Development plan's quality
bar says to always link official documents. Older public-access table places
the committee gate at recent activity and says everything above it is shown.

**Observed:** [meeting show](../../app/views/meetings/show.html.erb) disables
official PDF/city/recording chips and omits their hrefs for gated visitors;
[committee show](../../app/views/committees/show.html.erb) withholds the current
roster as well as recent activity. [Gated meeting items](../../app/views/meetings/_gated_items.html.erb)
keep every structured item/speaker with shortened body, while the older access
table describes withholding everything below the initial summary.

**Unsettled:** source URL availability and teaser/roster boundaries have newer
code comments asserting owner intent but inconsistent canonical descriptions.
Do not normalize either side into a definitive acceptance criterion solely by
reading code, and do not imply that underlying city records have become private.

**Next evidence:** settle the exact anonymous source-navigation and roster/item
rules, update the authoritative surface specification, then test allowed/withheld
bytes, identities, quantities and links under RES-07/09/11. No policy change was made here.

## V-06 — Preserved admin topic actions are not current UI journeys

**Observed:** admin design's [shipped corrections](../superpowers/specs/2026-07-26-admin-ui-revamp-design.md)
explicitly preserve `bulk_update`, old `merge`, and `create_alias` routes/actions
after their original controls were removed/superseded. The current detail UI uses
the repair workspace; candidate/promote/move/flip/remove paths are distinct.

**Intended boundary:** retained dispatch does not prove accessible multi-select
or alias-create UI. Tests for a preserved action would not demonstrate a clickable journey.

**Next evidence:** inventory links/controls when that planned UI ships; map the
new trigger, selection state, result and failure path before assigning coverage.

## V-07 — Expired approval-link replacement journey differs from the design

**Required:** passwordless design describes an expired approval-link page with
Send me a fresh link, without restarting normal sign-in.

**Observed:** [SessionsController](../../app/controllers/sessions_controller.rb)
redirects invalid/expired sign-in GETs to normal sign-in. The preserved
`resend_expired_magic_link` route only redirects with a Check your email notice;
its method does not create or deliver a new link. Approval currently uses ordinary
sign-in-purpose links and the normal confirmation view.

**Next evidence:** settle dedicated replacement versus normal sign-in recovery;
reproduce the expired approval experience with captured local email data and
verify any claimed replacement was actually created/delivered/usable. AUTH-02/08.
No endpoint behavior was changed during mapping.

## V-08 — Notification cooldown does not demonstrate eventual notification

**Required:** application design calls for batching no more than once an hour
while surfacing completed applications within about an hour.

**Observed:** [AdminApplicationNotificationJob](../../app/jobs/admin_application_notification_job.rb)
returns while a cooldown is active. There is no visible delayed re-enqueue in
that branch or recurring application-notification entry in
[recurring.yml](../../config/recurring.yml). Application submission queues one invocation.

**Inference needing runtime validation:** a submission during cooldown could
remain unnotified until another invocation occurs. This is not a demonstrated
lost notification or a claim about external production scheduling.

**Next evidence:** isolated clock/queue scenario: successful batch, another
submission during cooldown, passage of an hour without another submission;
inspect pending jobs and delivered batch. Also simulate delivery failure and
decision compensation/browser handling. AUTH-07/08, ADM-02 and BG-06.

## V-09 — Security controls and accepted known contexts use different predicates

**Required:** remembered (network, browser) pairs may satisfy strict context;
fresh proof is independently required for credential add/remove.

**Observed:** [credential controller](../../app/controllers/passkeys_controller.rb)
accepts matching anchor OR known context through its strict gate. But
[SecurityController](../../app/controllers/settings/security_controller.rb)
unlocks page controls only when fresh AND `session_context_matches?`, without
the known-context alternative.

**Inference:** a known pair that differs from the session anchor may receive an
extra Confirm it's you UI even though the controller would accept the operation.
This is not evidence of an authorization bypass.

**Next evidence:** define intended UI/endpoint alignment and exercise fresh
anchor, known different pair, unknown pair and stale proof; AUTH-10/12.

## V-10 — Resident-context topic edit has an unresolved account accessor

**Observed:** [TopicsController#update](../../app/controllers/admin/topics_controller.rb)
sets `added_by` from `Current.user&.email` when source notes become present.
The inspected [User](../../app/models/user.rb) and
[schema](../../db/schema.rb) use `email_address`; no `email` accessor/alias was
found in application code. This branch is outside a blank-context edit path.

**Inference needing reproduction:** saving nonblank resident context may fail
even if ordinary name/description edits succeed. No 500 was reproduced here.

**Next evidence:** ADM-06 browser form with active admin and source notes changed
blank→nonblank; inspect saved provenance and subsequent reload, then independently
validate a scoped fix if confirmed.

## V-11 — Existing suite execution/effectiveness still needs its own audit

**Observed configuration:** [local CI](../../config/ci.rb) and
[GitHub CI](../../.github/workflows/ci.yml) invoke `bin/rails test`. No `test/system`
directory, `application_system_test_case.rb`, browser test harness or explicit
system-test CI step was found. [Application config](../../config/application.rb)
sets `config.generators.system_tests = nil`, suppressing generated scaffolds;
that setting is not an instruction to abandon behavioral testing.

[Test environment](../../config/environments/test.rb) disables CSRF protection
and uses null cache. [Test helper](../../test/test_helper.rb) can manufacture a
signed-in session/passkey directly. These are legitimate development conveniences
but do not demonstrate real sign-in, browser DELETE, CSRF, rate-limit persistence,
provider delivery or WebAuthn behavior.

**Next evidence:** map actual test method/assertion and runner discovery to each
workflow and boundary, rather than declaring all controller tests isolated or
all integration tests complete. Compare baseline versus representative deliberate
defects and preserve TDD. No test totals, pass status or coverage percentage is
claimed by this documentation-only change.
