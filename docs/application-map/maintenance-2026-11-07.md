# November 7 maintenance verification

Base revision: `046318523c9b6d5773d25a471909ed96a5bd8f75`. Local changes
update the locked Rails components from 8.1.4 to 8.1.4.1 and repair a
calendar-dependent scraper test. Council-profile planning is separate.

## Required behavior and changes

The [development plan](../DEVELOPMENT_PLAN.md),
[account requirements](../superpowers/specs/2026-07-23-passwordless-auth-and-applications-design.md),
[public access requirements](../superpowers/specs/2026-07-24-tiered-public-access-design.md),
and existing source-preservation rules remain binding. The framework patch must
preserve sign-in, access boundaries, resident navigation, uploads, and background
processing. Relevant workflows include AUTH-01–05, RES-04/06/07/11, ADM-14,
and BG-01–04. Existing HTTP, service, and browser suites exercise those boundaries;
their passing results do not establish coverage of every framework advisory.

[Rails 8.1.4.1](https://github.com/rails/rails/releases/tag/v8.1.4.1)
addresses the advisories reported by the refreshed gem audit. Only the thirteen
Rails component versions, their exact interdependencies, the upstream sanitizer
requirement, and their package checksums change in the lockfile. Other gem
versions remain unchanged. Development eager loading succeeds with the app's
existing `vips` variant processor.

The BG-01 Committee on Aging discovery test paired a fixed November 2, 2026
meeting with `1.day.ago` as its cutoff. Once that date passed, discovery correctly
returned `:stop` before the test reached name correction. The cutoff now derives
from the fixture's meeting date. Both discovery attempts still assert reuse of
the same record, no additional meetings or jobs, corrected committee identity,
and preserved meeting/topic links. Production discovery code is unchanged.

## Local verification

Environment: Linux, Ruby 4.0.9, Rails 8.1.4.1, local PostgreSQL test databases.
Application and browser suites run serially. Provider responses and email delivery
use the existing test substitutes; no paid AI calls or real emails are claimed.

| Command | Result |
| --- | --- |
| `bin/rails test` | 2,174 tests, 13,574 assertions, no failures/errors, one existing missing-meeting-fixture skip in `PromptRunTest` |
| `bin/rails test test/services/scrapers/committee_on_agenda_name_test.rb` | Seven tests, 80 assertions, no failures/errors/skips |
| `CHROME_BIN=/usr/bin/chromium SE_CHROMEDRIVER=/usr/bin/chromedriver PARALLEL_WORKERS=1 bin/rails test:system` | 22 browser journeys, 760 assertions, no failures/errors/skips |
| `bin/bundler-audit check --update` before the patch | Failed on Rails 8.1.4 advisories |
| `bin/bundler-audit check` after the patch | No vulnerabilities with advisory database revision `516ea4757d5eec778c49af8371c23309c4b70f42` |
| `bin/importmap audit` | No vulnerable packages |
| `bin/rubocop` | 633 files, no offenses; changed test also linted after its fixture correction |
| `GEM_SPEC_CACHE=/tmp/trr-gem-spec-cache bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error` | No errors or warnings |
| `bin/rails runner 'Rails.application.eager_load!'` | Development boot and eager loading pass |

The final browser run used matching Chromium/ChromeDriver 155 binaries. An
initial run served ignored compiled assets from October 24, missing the current
Wire footer styles, and failed the existing layout assertion. Preserving those
generated assets outside the checkout allowed the tests to serve current source
assets. A subsequent attempt let Selenium select driver 157 for browser 155 and
could not create sessions; explicitly selecting the installed driver resolved
the environment mismatch. No layout assertions or product CSS were changed.
Browser journeys cover real local HTTP, cookies, forms, navigation, responsive
layout, and simulated WebAuthn ceremonies; they are not live-provider verification.

The initial full application run failed only the date-dependent discovery test.
Its focused run reproduced that failure. After fixing the cutoff, the focused
suite passed. A process-local fault replaced
`Scrapers::CommitteeOnAgendaName.correct` with an identity function; the selected
test failed on the expected corrected committee name, with no boot/runtime errors.
The process exited without changing production source files. Running the selected
tests again with the clock advanced to January 1, 2030 passed: two tests,
23 assertions. The final full application run above also passed.

The fault command was:

```sh
bundle exec ruby -Itest -r./test/services/scrapers/committee_on_agenda_name_test.rb \
  -e 'Scrapers::CommitteeOnAgendaName.define_singleton_method(:correct) { |title, _url| title }' \
  -- -n /bc-coa/
```

For the restored future-date check, the same runner used
`-e 'extend ActiveSupport::Testing::TimeHelpers; travel_to(Time.zone.parse("2030-01-01 12:00:00"))'`
and `-- -i /bc-coa/`.

## Pending integration

These local results were recorded before publication. Hosted CI and the
production image build must pass on the published revision before merging or
release. The checks above did not deploy the application.

[PR #230](https://github.com/AndreRobitaille/TwoRiversReporter/pull/230)
contains shared deployment tooling. Its published checks passed, and its exact
head `b15b01787ebe9d6cf7106bdf619fa0dc8edbd8ac` passed the local
`bundle exec ruby test/release_session_test.rb` runner: eleven tests,
100 assertions. These tests simulate remote transport. Its older green checks
predate the newly reported Rails advisories and the scraper fixture cutoff.

[PR #232](https://github.com/AndreRobitaille/TwoRiversReporter/pull/232)
contains runtime pins. Its CI and image workflows await workflow approval.
The runtime updater's current dry run also finds a newer Ruby image digest than
the PR pins, so refresh that branch and validate it after the Rails/test fixes
land. Newer optional gems are not automatically CI blockers; the intentional
`net-ssh` pin remains unchanged.
