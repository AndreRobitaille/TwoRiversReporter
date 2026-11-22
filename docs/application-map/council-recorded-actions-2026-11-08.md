# Recorded proposals and requests — November 8, 2026

Scope: BG-09 → RES-10/11, #240/#243 under #234. The
[binding design](../superpowers/specs/2026-11-07-council-accountability-design.md#important-issues-advocacy-and-follow-through)
requires attributed work beyond votes, including unsuccessful proposals, while
keeping member actions, campaign relationships and issue outcomes separate.

## Behavior and cost

New shared official-minutes requests extract distinct actions alongside project
milestones. The same source request and receipt serve every person; there is no
per-member request, extra scheduled job, new table or AI call on reads. The output
retains proposals, amendments, requests for analysis/agenda items, explicit
opposition and substantive follow-up, including failed proposals. It excludes
ordinary votes, seconds, procedural motions and unattributed group discussion.
An exact source label and contiguous passage are required, with approved agenda
topic identities and a known event date. Location validation does not independently
establish the model's semantic accuracy; real-provider evaluation remains open.

Known exact names/aliases or a unique surname resolve on read without creating
people, aliases or office records. Ambiguous/unknown names remain in the shared
result but do not appear as a named member's action; unrelated resolved acts still
appear. A corrected alias takes effect on the next read without re-extraction.
Actual sourced service dates control inclusion, including retrospective actions
reported later. Topic overlap or a speaker identity does not establish a campaign
connection. Neither a request nor a losing proposal proves completion.

The main record displays at most three short actions under Work beyond votes,
with further actions and source passages in independently controlled disclosures.
No vote or existing campaign statement is required for an action to appear.
Gated visitors receive none of these claims; permitted users and verified Google
receive the same saved source-backed text under the existing access contract.

The response schema is retained on newly prepared requests but excluded from
source identity. Extending the schema or changing a prompt/model does not reopen
completed historical analyses. Older milestone-only results remain useful and
do not suddenly claim advocacy coverage. Collecting their missing actions would
need an explicitly scoped later run; no such run is enabled here.

Existing request/run/day/month reservations, the 8,000-token response cap and
two-attempt limit apply. On the same complete official Recreation Board sample
used in #291, offline construction estimates $0.136623 for one request and
$0.273246 for both possible attempts at the checked November 8 rates, valid
through November 21. The previous prompt's comparable ceiling was $0.13204.
This is a conservative allowance estimate, not actual billing or a monthly
forecast. Advocacy adds instructions/output within the same request, not another
request for each person. No allowance or live processing policy was enabled.

## Executed verification

Isolated branch `codex/council-recorded-advocacy`, base `c0644f8`, Ruby 4.0.9,
PostgreSQL `trr_council_recorded_advocacy_test`. Transport alone is deterministic;
preparation, spending reservations, receipts, validation, persistence, identity
resolution and later HTTP reads execute normally. The real preview database is
untouched. No paid generation, production operation, broad backfill, merge or
deployment ran.

- `bin/rails test test/integration/council_recorded_actions_test.rb
  test/integration/council_issue_updates_test.rb
  test/integration/campaign_action_matching_test.rb
  test/jobs/reconcile_campaign_sources_job_test.rb
  test/lib/prompt_template_data_test.rb`: **32 tests, 346 assertions**, green.
  One source retains two distinct actions and two outcomes in one request;
  both members receive only their own action even with no votes. Checks cover
  unknown/ambiguous identities, alias correction, service dates, source correction,
  unchanged/legacy reuse, malformed output and private/verified-Google reads.
- After simplifying shared passage validation, the two evidence integration files
  passed: **18 tests, 191 assertions**.
- `bin/rails test test/system/member_recorded_actions_journeys_test.rb
  test/system/member_issue_updates_journeys_test.rb`: **2 tests, 16 assertions**,
  green. The phone journey verifies short visible text, closed/open/closed source
  disclosure, correct source link and no horizontal overflow. Chromium 157 with
  installed driver 155 warned about version compatibility but executed normally.
- Removing speaker-in-quote validation caused the intended invalid-response
  assertion to fail. Bypassing visitor gating exposed the section and failed the
  intended absent-section assertion. Each isolated fault was restored and the
  affected integration files reran green. Initial Ruby test-block syntax and
  missing service-end fixture provenance were corrected; these setup errors are
  not counted as defect detection.
- Full `bin/rubocop`: **829 files**, clean. Prompt definition tests, documentation
  links (242 local targets) and `git diff --check` were checked. The isolated
  test database initially lacked populated templates; after local-only
  `prompt_templates:populate`, `prompt_templates:validate` passed. No migration
  is introduced. A captured phone screenshot was inspected after the focused
  journey reran green (1 test, 7 assertions).

## Official reference and limits

The [December 1 packet](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Packet-7f330ca5db25423e8ee9dbcbc77975e9.pdf)
publishes November 24 work-session minutes on pages 15–19. Pages 18–19 record
Bittner's advocacy for reconsidering library funding and the lack of a clear
consensus. The selected official excerpt is a deterministic fixture, retaining
November 24 as the action date rather than the packet date. It checks the pipeline
without inventing a new vote, funding outcome or promise conclusion. It is not a
complete-source model evaluation or a populated real profile.

No automatic campaign-to-advocacy matching, complete discussion coverage,
staff-recommendation comparison or formal-case extraction is claimed. These
remain parent-issue work. An absent action is not proof of inaction. Real profile
population and the other session's voter review remain unverified for this slice.

## Review follow-up

The all-records selection now includes actions across every evidenced selectable
service period, rather than hiding the section when no single term is selected.
Gaps between terms remain excluded. The added two-term scenario passes in the
8-test/83-assertion action integration file; restoring the old guard fails its
expected two-action count, and restoration returns the file to green. Targeted
RuboCop passes. This correction changes eligibility scope without another AI call.
