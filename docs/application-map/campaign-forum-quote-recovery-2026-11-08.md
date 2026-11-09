# Retained forum quotation recovery — November 8, 2026

The subsequent [bounded source review](council-source-acceptance-2026-11-08.md)
accounts for the eight remaining passages, recovers six through explicit
editorial corrections, and records the current inputs and spending hold.

Scope: #239/#238 under #234; BG-08, ADM-21 and RES-10/11. Based on
`394092a` (saved minutes motions). This is local implementation/verification,
not deployment or a complete campaign-coverage assessment.

## Requirement and demonstrated problem

The [campaign contract](../superpowers/specs/2026-11-07-council-accountability-design.md#campaign-collection-and-forum-attribution)
requires source passages, qualifications and externally verified attribution.
The owner supplied and personally labeled both 2024 forums. Their retained
provider responses contain quotations shortened with ellipses. The exact-text
validator held those statements even where each fragment uniquely identifies
an ordered passage inside one verified speaker's answer. This includes the
growth-committee proposal; another forum-analysis call is unnecessary.

The parser now expands such excerpts to the exact contiguous source passage,
including the omitted words. Fragments must be unique and ordered inside the
located answer, and the whole resulting passage must belong to the verified
speaker. Ambiguous, reversed, cross-speaker and unverified excerpts remain held.
Article quotation rules are unchanged. Location does not validate the model's
interpretation or establish that every material statement was extracted.

## Retained recovery and cost behavior

An operator can run:

```sh
bin/rails 'council_profiles:recover_forum_quotes[SOURCE_ID,ACTIVE_ADMIN_ID]'
```

This reparses the saved response, creates a retained version only if more
statements become located, and publishes supported statements through the
existing pipeline. The source text, original uploaded file, labels, timestamps
and old results remain intact. Repeating recovery does nothing. The normal
extraction path also handles abbreviated quotes in future provider responses.

Topic preparation reuses completed matching decisions for unchanged statements
from the same source. Positive, negative and unresolved results are retained;
only new/changed statements enter the request. Existing links remain usable
while that request is paused. Unfinished provider output cannot publish links.
Later metadata edits prefer the latest saved extraction, preserving recovery.
Existing semantic action keys already exclude projection/version IDs, so no
action results are copied or rewritten.

The command does not supply a paid allowance. New topic matching uses the
existing job and admission controls; there is no new schedule, prompt or table.
Run only in the intended environment. Production and historical-run permissions
are unchanged.

## Real local data

A disposable copy of the existing local preview was checked with provider
construction forbidden. No production database was accessed or copied.

| Forum recording | Statements retained | Located before → after | Newly located |
| --- | --- | --- | --- |
| [March 7 recording](https://www.youtube.com/watch?v=L7V9c2_RGWE) | 76 | 41 → 74 | 33 |
| [March 12 recording](https://www.youtube.com/watch?v=L9Tlws24jm4) | 100 | 90 → 94 | 4 |

The 37 recovered records comprise 23 for elected members and 14 for Andrew/Jeff.
All previously located statements survived. Eight source passages remain held;
unknown existing-person identities remain separate exceptions. No person or
service record was invented. Event labels above identify the recordings and do
not resolve the previously noted organizer/title uncertainty.

Including HTR, current accepted statements became 46 for Bittner, 30 for Brandt
and 41 for Derby. Existing public connections remained two, four and zero,
respectively. Original accepted statement content and topic links were unchanged.
The two new matching stages retained 133 decisions and prepared just 33 and four
new candidates. Both paused with zero attempts/requests. Vote, member, provider
request, spending-reservation and saved action-review counts were unchanged.

The offline preflight estimated $0.526633 for those two topic requests, or
$1.053266 with two attempts each, using the previously checked November 8 rate
configuration and conservative byte-based input allowances. These are one-time
planning ceilings, not measured charges, dispatch authorization, a current-price
guarantee or a recurring monthly estimate. Additional specific action comparisons
are separate. No paid call ran.

Real Chromium journeys at 390px and 1280px covered all three profiles: correct
statement counts, recovered summaries, independent source/question disclosures,
recording links, preserved Brandt grant votes and their official minutes source,
and no horizontal overflow. Screenshots were inspected. New unmatched statements
are in the existing full-statement disclosure; no unsupported issue/action
connection was added to promote them into the main issue panels.

## Execution evidence

Ruby 4.0.9 / Rails 8.1.4.1 / PostgreSQL; deterministic provider transport for
tests, actual local civic data for the six browser journeys. Ordinary and system
tests used an isolated synthetic database and ran serially.

- `bin/rails test` with the forum recovery, campaign topic/update/extraction,
  action/issue matching, cost preflight and four extraction/publication/recovery
  job files: **55 tests, 625 assertions, no failures/errors/skips**.
- Full `bin/rubocop`: **875 files, no offenses**.
- `CHROME_BIN=/usr/bin/chromium bin/rails test test/system/prepared_campaign_forum_journeys_test.rb`:
  **one journey, 29 assertions, no failures/errors/skips**. The preceding system
  invocation selected the default incompatible Chrome/driver pair and was
  stopped at browser setup; it is not counted as app verification.
- Representative test-only faults: bypassing speaker containment incorrectly
  located a cross-speaker excerpt; dropping retained topic decisions expanded
  the paid request from `[1, 3]` to `[0, 1, 2, 3]`. Each intended assertion failed;
  both changes were restored and the selected tests passed again.
- The recovery test crosses the operator task, real parser, retained versions,
  publication, paused matching, later HTTP reads, deterministic matching and
  metadata-only reuse. Its old-parser stub is setup for the legacy failure;
  recovery itself is not stubbed. A separate fresh extraction tests the normal
  provider-to-publication path.

The browser CLI could not write its runtime socket in this environment; the
repository's Capybara/Selenium approach supplied actual Chromium interaction.
No new UI or transcription editor was introduced. Remaining source ambiguity,
semantic omissions, paid matching, recurring workload validation and final stack
review/integration remain open in the parent/children.
