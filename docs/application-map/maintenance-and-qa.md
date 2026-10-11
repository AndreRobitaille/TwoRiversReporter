# Maintaining the map and using it for subsequent QA

The original discovery deliverable is the application map. The [overnight audit](overnight-progress.md) now applies this method to prioritized workflows; the process below remains the ongoing review method. It does not install an automation, allocate reviewers,
change CI, run paid providers, or declare existing tests inadequate by count.
Ordinary TDD continues throughout development.

## Maintain behavioral documentation

1. Record the revision/environment and start from product/specialized requirements.
   Inspect the user-visible triggers and complete tasks independently of test names.
2. For a feature or permission change, identify affected stable workflow IDs,
   actor/state combinations, navigation/controls, data dependencies, representations
   and downstream transitions. Add a new ID for a new task; do not renumber old ones.
3. Update intended contract and implementation observation separately. Cite the
   actual requirement and changed controller/view/job. If only implementation
   exists, mark acceptance as a candidate pending independent/product review.
4. Keep removed/unfinished/orphan surfaces explicit. Retire IDs with a destination
   or reason so historic coverage reports remain understandable. Refresh route
   inventory and review static files/middleware/contextual UI, not only sidebar links.
5. Have a reviewer independently reconstruct the expectation from requirements
   and the user task before inspecting implementation/test assumptions. Record
   disagreement in the verification register; do not auto-approve docs because
   an implementation and its tests agree.
6. Attach exact execution evidence to later verification. Update baseline date/
   revision only after reconciling changes since the previous baseline; preserve
   unresolved decisions and historical evidence links.

This separation is a review responsibility, not a guarantee that merely using
another agent produces independent reasoning. A reviewer needs the product
expectation and direct observations, not only the development agent's narrative.
Ownership/reviewer assignment remains open.

## Existing-test quality review

Create a review record per workflow and meaningful variant. Use this schema:

| Field | Evidence to record |
| --- | --- |
| Workflow / variant | Stable ID, audience, mode, starting data, intended transition |
| Expectation provenance | Requirement section or owner-reviewed candidate, unresolved decisions |
| Test implementation | Exact file, class/test method, fixture/setup, assertions and material stubs |
| Level / exercised boundary | Model/service, real HTTP integration, browser or background/provider boundary; specify what it actually crosses |
| Starting-state proof | Evidence that the allowed data/action was present and usable before loss/gating |
| Outcome assertions | State persisted/removed, correct identities/counts/content, visible message/navigation, subsequent access |
| Runner discovery | Exact command, discovered/executed test, local versus CI, skip/filter status |
| Execution result | Revision/environment/date, result/trace; environment failure is not a product defect |
| Representative fault | Isolated mutation and expected failing assertion; clean baseline and restoration evidence |
| Coverage status | Unknown, absent, component only, partial journey, verified journey; keep defect-detection status separate |
| Gap / proposed work | Missing boundary/variant/assertion, risk priority, smallest useful next verification |
| Cleanup disposition | Keep/refactor/strengthen/consolidate/remove; exact assertions, rationale, retained variants and before/after evidence |

At the initial baseline **all coverage/effectiveness entries are unknown**; this
schema has not been filled from existing tests. Review each test's assertions;
a file path or class name cannot establish the level or adequacy of coverage.
HTTP integration can cover a complete state transition without a browser, and
browser tests can still assert too little.

Questions for the review:

- Does it begin in the documented real starting state, or bypass the very boundary
  at risk? For logout, a seeded session can help test server deletion, while a
  separate real control journey must still demonstrate method/Turbo/CSRF behavior.
- Does it prove state and later access, not just status/redirect/flash?
- Does a mock replace route dispatch, auth, persistence, queue completion, source
  matching, WebAuthn, clipboard, or delivery where the defect could occur?
- Is the test discovered by the documented runner and CI? Were skips or filters
  mistaken for passing evidence? Does it actually exercise the changed path?
- Are identities and distinct event counts preserved as well as canary text?
- Would a realistic broken outcome fail it? Where does that evidence come from?
- Are many near-identical component assertions crowding out a missing primary task?

### Simplification and cleanup review

The existing-test audit in [GitHub #168](https://github.com/AndreRobitaille/TwoRiversReporter/issues/168)
also reviews opportunities to simplify tests and assertions. Establish what each
test proves before recommending cleanup, and record exact tests/assertions with a
keep, refactor, strengthen, consolidate, or remove disposition.

Review repeated setup, unrelated fixtures, redundant assertions, brittle selectors,
incidental row counts, exact wording checks, and mocks that bypass the boundary
under review. Compare each assertion with its intended contract: quantity,
identity, required wording, permissions, persistence, and later requests may all
be material. Small helpers should make the actor, starting state, exercised
boundary, and outcome easier to understand.

Preserve distinct roles, modes, state transitions, identities, edge cases and
failure variants. Consolidation or removal needs evidence of equivalent behavioral
coverage. Record before/after assertions, retained or improved coverage, runner
discovery, and remaining gaps; file material implementation work as small linked
follow-ups after the review.

Validate implemented cleanup with passing baselines and the same representative
defect experiments before and after. The intended behavioral assertions must
still fail for meaningful faults. Record restoration and passing reruns, plus
RuboCop results for changed Ruby. The original scope addition did not change test code; the overnight audit now records one proven duplicate removal and a strengthened challenge assertion, with before/after fault evidence.

## Derive new behavioral tests from the map

Choose the cheapest level that crosses the risky boundary and can assert the
documented outcome. Use browser journeys where routing from a visible control,
Turbo/Stimulus, CSRF/cookies, native credentials, clipboard, dialogs or responsive
navigation matter. Use HTTP integration for persistent state/redirect/authorization
transitions, and deterministic job/service evidence for background/data stages.
Record which provider/browser portions remain simulated or unverified.

Initial high-value scenarios:

| Workflow | Meaningful assertions | Appropriate boundary |
| --- | --- | --- |
| AUTH-01/02/04/05 | Real sign-in controls, one-use confirmation, own protected read, both sign-out controls, old cookie denied, next protected read denied; open/gated distinction | Browser plus HTTP/session-state evidence |
| AUTH-06/07/08 + ADM-02 | Verified form → correctable error → submission → admin reason/decision → delivered usable link → first full read; denial/reapplication and notification failure | Browser/forms with deterministic captured delivery; explicit real-provider evidence separately |
| AUTH-10/12 | Own credential ceremony, foreign ID denied, stale/known/unknown context, no challenge loop, last usable admin safe, subsequent sign-in | Secure-origin browser/WebAuthn and real HTTP authorization |
| AUTH-13/14/15 + RES-13 | One-time reveal/copy, metadata lacks secret, old key reads before revoke and fails after, owner eligibility, no admin/write authority | Browser key management plus authenticated API requests |
| RES-07/08/11 | Correct supplied source, unresolved changed source, cancellation across representations; allowed content first, withheld bytes and fixed identities/caps later | HTTP/HTML/API projection, browser source navigation |
| ADM-03/04/07 | Persisted deletion/permission changes, surviving unrelated references/audit, merge identities/history/old URL, refused action leaves no false audit | HTTP/integration plus visible confirmation control |
| ADM-14 + BG-02/03/04 | Caption/SRT and proposal evidence → every distinct analysis item → appearances/topic summaries → briefings → resident/API; closing action survives | Isolated deterministic pipeline and browser workflow/status |
| RES-14/15 | Child freshness discovers old event; assembled Unicode transcript equals selected revision, including ending; version conflict restarts | API integration with changing source state |

Data setup must be explicit and synthetic. Include multiple distinct events,
relationships and awkward states, not only one happy fixture. Bind local servers
to `0.0.0.0` for remote access, but exercise passkeys on a secure `localhost` origin
or HTTPS per repo guidance. Use temporary attachments/test data and document
cleanup. Production data copying and live paid generation require explicit authority.

## Check whether a test detects a defect

Perform fault experiments only in an isolated local test environment. Establish
a clean baseline, apply one bounded defect, run the exact target test, confirm
the intended assertion fails for the intended reason, restore the defect, and
rerun to green. A boot/syntax error does not prove detection of a behavioral bug.
Do not leave a mutation mixed into unrelated work or run it against production.

Candidate representative faults for future audits (some auth/gating variants have now been executed and recorded in the overnight audit):

- AUTH-04: return a logout 500; separately omit session invalidation. A redirect
  assertion may catch one while missing the other. Exercise the actual link too.
- AUTH-05/15: allow stale session/ineligible key-owner access on the next request.
- RES-11: render withheld content into a share/meta/stream field; separately let
  page 2 rotate topic identities or make result shape depend on a hidden headline.
- ADM-03/07: drop a surviving reference/appearance or persist a false deletion audit.
- BG-03/04: drop the closing action or one distinctive agenda ID downstream while
  preserving polished prose; compare every major upstream→downstream boundary.
- RES-15: omit final chunk or mix revised text into continuation.

Follow existing [AGENTS.md verification rules](../../AGENTS.md): prove gated
content is present for an allowed user before absence assertions; remove the
guard and prove the test fails; test quantity and identity separately from text.
Never combine code coverage, workflow coverage and defect detection into one score.

## Runner facts and verification scope

At the discovery baseline, local/GitHub CI ran application tests without browser coverage. Merged PR #177 adds an explicit `bin/rails test:system` step locally and in GitHub, Selenium/Capybara/Chrome setup and documented invocation. Current local `bin/ci` performs setup, application/browser tests, RuboCop, gem/importmap audits and Brakeman; GitHub runs application/browser tests against PostgreSQL and the lint/security jobs. Historical V-11 records the original absence. Exact current-head discovery/failure/restoration evidence is in the overnight audit.

Adding a browser suite later requires deliberately choosing its harness and CI
invocation and proving discovery; a new file alone is not evidence it runs.
Repository changes to Ruby/model/job/service code require targeted Minitest and
`bin/rubocop`. Multi-stage changes require preservation evidence at each boundary.
This documentation change ran only the checks listed in [README.md](README.md).

## Recurring review remains a decision

A useful proposed split is a small change-based review that reconciles modified
workflow IDs/map drift/runner discovery, plus deeper periodic journey and
fault-detection reviews for priority areas. A nightly pass would evaluate gaps
and effectiveness rather than merely rerun the unchanged suite.

Before scheduling, settle cadence, trigger/base revision, independent reviewer,
local/staging environment and cost limits, report location, deduplication, and
what merits notification. Report actionable new gaps, failures, decisions or
completion; avoid repeated unchanged status. No recurring review or automatic
map rewrite was created as part of this request.
