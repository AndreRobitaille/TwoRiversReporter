# Inspectable peer voting comparisons

Scope: RES-10 and RES-11, #241 under parent #234. Binding requirements:
[agreement with other members](../superpowers/specs/2026-11-07-council-accountability-design.md#agreement-with-other-members).

## Behavior

The selected Council term adds a closed **Voting with other members** section
below the decision record. Peers with documented overlapping service appear
alphabetically, with same-vote fractions for all compared substantive decisions
and for decisions with both yes and no votes. There is no leaderboard, percentage,
majority label or inference about independence. A zero denominator is unavailable.

Each fraction opens `/members/:id/compare/:peer_id`, preserving `term`. The reader
can switch between all and divided votes, page through 25 decisions, inspect the
actual ballots and separately recorded Council outcome, and open the meeting.
Agenda context makes the heading readable; exact motion wording stays available
in a disclosure. **What counts here** explains and lists exclusions. Back returns
to the selected member period. All-records mode does not silently use one term
for comparisons; it asks the reader to select a documented term.

Arithmetic uses the existing structured vote record, not featured cards or topic
links. Both people must have known yes/no votes within documented shared service.
Attendance-derived ballots and routine procedural motions, including consent
agenda approval, are excluded. Separately recorded amendments remain separate
decisions. Multi-topic associations do not multiply motions. If multiple imported
copies of one meeting contain votes, the entire ambiguous meeting stays outside
fractions and is disclosed until reconciled; saved vote records remain available.
This is a conservative comparison rule, not a new automatic reconciliation system.

Reads calculate from current persisted facts. A vote, service date or motion
classification correction changes subsequent comparisons in both directions.
There are no generated summaries, stored comparison caches, jobs or AI calls.

Gated anonymous responses contain no fractions, decisions or exclusion evidence,
including alternate formats. Authorized/open readers and verified Google see the
same server-rendered evidence. Canonical member pages provide crawlable links to
these derived views; pair/term/filter combinations are not added to the sitemap.
Actual Google indexing and AI-result inclusion are outside local verification.

## Verification

Base `27df665` plus this patch; Ruby 4.0.9, PostgreSQL, isolated synthetic test
database. Providers are forbidden during comparison tests and the real-data read.
The final HTTP/helper regression ran 32 tests with 489 assertions; the two browser
journeys ran 31 assertions. Both passed with no failures, errors or skips.
RuboCop inspected 806 files with no offenses. The local browser runner warned
about the installed Chrome/driver versions, but both journeys executed fully.

- HTTP fixtures independently expect 2 same votes among 3 shared decisions, and
  0 among 1 divided decision. Abstention, recusal, absence, missing/inferred votes,
  service eligibility and procedural exclusions are inspected. A tied official
  failed motion remains failed without majority language.
- Persisted ballot, service-date and motion-classification corrections change
  later requests. Reimport and multiple topic links do not multiply decisions;
  a second vote-bearing meeting copy holds the comparison while preserving the
  raw saved record. Separate amendment and consent cases exercise their counts.
- Access checks prove content first, then its absence from gated HTML/JSON/Turbo.
  A verified Google request follows a member link to evidence; spoofed identity
  cannot. Google IP data is supplied deterministically without external transport.
- Phone browser journey opens the closed section, follows the fraction, changes
  page, selects divided votes, visits a meeting, returns, opens exclusions, and
  returns to the selected term. It checks decision identities and overflow.
- Representative defects: weakening yes/no eligibility makes the expected 2/3
  become 2/6; removing the reporting gate exposes the result after allowed-content
  proof. Both intended assertions fail, then pass after restoration. No faults
  were applied to the real-data preview.
- Real development data was read without mutation or AI. All three initial-cohort
  pairs were inspected; an independent SQL count confirms the displayed arithmetic
  over the selected decision IDs. This is not independent proof that every source
  was extracted correctly or that the full term is present. No ambiguous imported
  meeting copies occurred in this sample. Phone and desktop previews were visually
  inspected with actual agenda titles, ballots, outcomes and source links.

Commands:

```sh
bin/rails test test/integration/member_peer_votes_test.rb test/integration/member_council_period_test.rb test/integration/member_recorded_votes_test.rb test/controllers/google_crawler_access_test.rb test/helpers/members_helper_test.rb
bin/rails test test/system/member_peer_votes_journeys_test.rb test/system/member_council_period_journeys_test.rb
bin/rubocop
```

The separate resident-review session's app transport was unavailable, so this
new surface has not received its persona review. Full-term source coverage,
arbitrary date ranges, staff recommendation comparisons and resolving ambiguous
consent/amendment extraction remain separate work. No paid AI, historical
backfill, production operation, merge or deployment ran for this slice.
