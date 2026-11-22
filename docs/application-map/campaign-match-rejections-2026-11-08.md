# Reviewed campaign connections — November 8, 2026

The real catch-up exposed overbroad matches: an affordable-housing TIF extension
was connected to a named development site and remote-worker recruitment; routine
financing-district closures and a budget vote were treated as evidence for broader
campaign claims. An exact source quotation alone does not validate that connection.

The resident question is whether a recorded action addresses what the person
actually advocated. This fixes demonstrated misleading connections under #240 and
#243. It does not add a complete-term verdict or require exhaustive action review.

`CampaignActionReview#reject_matches!` records an administrator's reason for specific
pair keys and an existing audit event. Later vote and issue-evidence reads treat
those pairs as not direct. The original provider response, completed cache and
unrelated pairs remain intact. Source metadata changes reuse the same semantic
pair keys, so corrections survive without another call. This is an operator repair
method, not a new administrative interface. Normal future matching guidance now
requires the stated target and effect, rather than just a common policy tool;
the changed prompt has not been evaluated with another paid run.

Affected workflows: BG-08 → RES-10. Validation on local PostgreSQL used deterministic
provider responses in a separate test database, based on `d7b76f3`:

- `bin/rails test test/integration/campaign_match_rejections_test.rb
  test/integration/campaign_action_matching_test.rb
  test/integration/campaign_issue_evidence_test.rb`: **19 tests / 180 assertions**,
  no failures, errors or skips. Allowed content is proved first; rejection removes
  the connection on later HTTP reads, preserves the statement and raw result, and
  survives cached replay and a metadata correction with zero provider calls.
- Removing the rejection filter caused the later member-page assertion to fail:
  expected zero action cards, found one. Restoration passed the two new tests
  (**24 assertions**). Invalid reviewer/pair keys leave the visible result intact.
- `bin/rubocop`: **880 files**, no offenses. Local test/preview migrations ran;
  schema formatting and the additive column diff were checked.

The approved real-data catch-up rejected 18 overbroad pairs across three shared
batches using this method. Its full results, coverage limits and spend are tracked
in the history proposal. These are reviewed local corrections; they do not prove
perfect automated matching or a deployed production correction.
