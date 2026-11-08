# Member campaign records: November 8, 2026

Application revision: `360110db` on the shared extraction branch from PR #274.
This advances #239 and the existing profile under #234; it does not complete
campaign/action/outcome comparisons or the historical backfill.

## Contract and delivered behavior

The [member enrichment direction](../DEVELOPMENT_PLAN.md),
[campaign evidence contract](../superpowers/specs/2026-11-07-council-accountability-design.md#campaign-collection-and-forum-attribution)
and [audience](../AUDIENCE.md) require shared source analysis, useful existing
member pages, preserved context and source links. The owner specifically requires
real civic data for development previews and acceptance, rather than treating
invented examples as proof that the feature works.

After extraction, `Campaigns::PublishStatements` checks source locations and
unique existing names/aliases, recording its automatic validation method and
date. Unmatched candidates and missing passages remain unresolved. It creates no
person, office or service period. Immutable source content stays separate from
the accepted member assignment; a member merge preserves original attribution.

RES-10 displays accepted statements from the current source version only, grouped
by election, with kind, conditions, timing, question disclosure and publisher/date.
Selected excerpts are labeled. A source correction removes the old display until
the new extraction passes validation. Earlier evidence remains retained. Page
reads perform no publication or AI work; unchanged jobs reuse the extraction and
statement rows. ADM-21 exposes unresolved identities and matched profile links.
RES-11 withholds the whole campaign section from gated anonymous readers, including
its source link and metadata. Existing API payloads remain unchanged.

## Real-data acceptance

Used a separate local database containing only existing civic tables from the
development database: people, aliases, offices, committees, meetings, agenda items,
topics, votes and attendance. No website accounts, credentials, production reads
or production database sync were involved. Existing development data was unchanged.

Checked the five candidates' answers to the challenges question in the
[March 27, 2024 HTR questionnaire](https://www.htrnews.com/story/news/politics/elections/2024/03/27/two-rivers-council-candidates-talk-about-the-citys-potential-as-the-april-2-election-nears/73099320007/),
using its April 7 archive. The input is explicitly selected excerpts, not a claim
to have processed the full article. Private excerpts and the checked reference
remain outside Git. The parser, publication job, actual database identities and
member HTTP responses executed against that reference; provider generation was
not performed or represented as verified.

| Existing member | Accepted statements | Existing recorded votes | Meetings with votes |
| --- | ---: | ---: | ---: |
| Mark Bittner | 3 | 208 | 49 |
| Doug Brandt | 2 | 210 | 48 |
| Shannon Derby | 2 | 210 | 45 |

All three profiles retained their real voting record and gained the correctly
attributed campaign section, election date and original publisher links. Four
statements for Jeff Dahlke and Andrew Quackenbush remained unresolved because
neither has a matching civic person locally. No new people were invented.
Repeated publication preserved row identities/timestamps and all existing civic
counts, with zero paid AI calls. The local vote dates start July 7, 2025 and run
through October 2026; these are available-record counts, not a complete term.
Missing history is a coverage limit, not a reason to wait for the full backfill.

The separate development preview combines this slice with PR #271's vote UI.
Actual browser reads of all three real profiles at 390px showed the expected
3/2/2 campaign cards and no horizontal overflow. Bittner's original-question
disclosure opened; Derby's numbered page-two link navigated to a new set of
25 real vote rows, retaining both campaign cards and one bottom-only pager.
The three profile screenshots and selected page-two control were inspected.
This combined preview is a local integration check, not a merged release.

## Repeatable implementation and workflow checks

Ruby 4.0.9, PostgreSQL, one test worker in an isolated test database:

- `bin/rails test`: **2,461 tests, 16,727 assertions, no failures/errors, one
  existing fixture-dependent skip**. This restored run followed the fault checks.
- Focused publication, member HTTP/merge/access, shared extraction, member/alias,
  member-controller/gating, resident API and admin view-hygiene files:
  **108 tests, 1,118 assertions, no failures/errors/skips**.
- `CHROME_BIN=/usr/bin/chromium bin/rails test test/system/member_campaign_journeys_test.rb test/system/campaign_extraction_journeys_test.rb`:
  **2 journeys, 66 assertions, no failures/errors/skips**. These deterministic
  regression fixtures exercise question expansion, actual source navigation and
  return, refresh, mobile navigation/logout and later denial at 390px. The phone
  screenshot was inspected; no horizontal overflow. Only external publisher and
  email/provider transport are simulated. Native passkeys are not exercised here.
- `bin/rubocop --cache false`: **749 files, no offenses**. The new table's schema
  was normalized with `bin/rubocop -A db/schema.rb`; only its table/index/FK changes
  remain. `git diff --check` passes.

After a clean focused baseline, process-only faults in ignored QA scripts proved
the new HTTP assertions detect a dropped second statement (four tests, three
intended count failures) and a removed campaign access guard (four tests, one
intended anonymous disclosure failure after allowed content was proven). No boot
error is counted as defect detection. Normal browser/full-suite runs then passed.

## Limits

The real-source check verifies retained evidence and publication, not model
accuracy, complete campaign coverage, automatic discovery or paid cost estimates.
The public cards do not compare actions, infer motives, or claim outcomes.
Prepared forums, topic matching, full-term eligibility/backfill and automated
nightly admission remain later slices. No paid AI, merge, deployment or production
operation occurred.
