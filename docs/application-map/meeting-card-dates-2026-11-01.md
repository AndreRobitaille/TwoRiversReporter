# Meeting card dates and Wire labels — November 1, 2026

## Acceptance and scope

The owner's live-site review identified inconsistent meeting dates on home and
Topics cards and wrapping "Full story" labels beside long committee names.
The owner requested both corrections and an explanation/prevention of the date
failure. The [Meeting contract](../DEVELOPMENT_PLAN.md#meeting) now makes the
Central Time calendar rule explicit. The approved
[homepage design](../superpowers/specs/2026-04-10-homepage-redesign-design.md)
requires meeting references and visible click affordances on desktop/mobile.

Affected workflows are RES-01 home discovery, RES-02 topic browsing, RES-03
search, RES-04 topic-to-meeting navigation, RES-05/06 meeting discovery/details,
RES-09 committee activity and RES-11 public/member access variants. Card dates
must match the associated meeting's Central Time date, retain the latest meeting
identity, and remain correct after another request. The complete "Full story"
label must remain readable/clickable without overlap or horizontal overflow.

## Root cause and audit

`HomeController#load_meeting_refs` and `TopicsController#build_meeting_refs`
select `meetings.starts_at` onto `TopicAppearance` rows. That model has no typed
`starts_at` attribute. PostgreSQL returns a plain UTC `Time`, bypassing the
time-zone-aware `Meeting#starts_at` attribute. The views called `strftime`
directly. Committee activity's `MAX(meetings.starts_at) AS latest_meeting_date`
has the same problem and is included in the correction.

A synthetic PostgreSQL transaction at the baseline produced:

| Read path | Ruby value/type | Direct date label |
| --- | --- | --- |
| Reloaded `Meeting#starts_at` | `2026-11-02T18:00:00-06:00`, `ActiveSupport::TimeWithZone` | Nov 2 |
| Projected `TopicAppearance#starts_at` | `2026-11-03T00:00:00Z`, `Time` | Nov 3 |
| Aggregated `Topic#latest_meeting_date` | `2026-11-03T00:00:00Z`, `Time` | Nov 3 |

All three values represent the same correct instant. Explicit `in_time_zone`
before formatting produces Nov 2 for all three. No stored date repair is needed
for this display defect. The November fall clock change makes 6 p.m. Central
cross UTC midnight; later evening meetings can also fail during daylight time.

This code predates the November 1 dependency release. The Home projection is
present in `347ad4bf` (April 10), Topics in `654f0aba` (April 12), and committee
aggregation in `3a6b58b0` (April 12). Comparing these controllers, affected views
and `config/application.rb` from pre-release `1d22bc45` through deployed
`6eff977218a25f9ebe3937bc15daab0cdaaa1cd6` shows no changes.

The existing Home/Topics/committee controller checks covered card content,
selection and navigation but did not assert these date labels against explicit
UTC-midnight fixtures. Thus green tests did not distinguish a correct local day
from the UTC day. The new expectations use literal UTC inputs and independently
specified local labels, including the date/month/year boundaries.

The `starts_at` projection/aggregate audit also checked:

- API committee aggregation uses its alias only for ordering; the alias is not
  formatted or emitted as a calendar date.
- Sitemaps and meeting archives select the actual typed `Meeting` attribute.
- Resident impact policy compares instants, without discarding the time zone
  into a date label. Admin job-run selection only picks a meeting ID.
- Topic upcoming, Next Up and meeting detail/list dates read the typed meeting
  attribute; they provide independent comparison surfaces for the regression.

`MeetingsHelper#short_meeting_date` now localizes at the formatting boundary for
all four affected partials/views. This keeps existing query selection and avoids
fixed UTC offsets that would break at daylight saving transitions. The page
playbook documents the projection pitfall and shared formatter. Wire footers
allow wrapping with a gap; the full CTA cannot shrink or break into words.

## Local verification

Baseline: `6eff977218a25f9ebe3937bc15daab0cdaaa1cd6` plus this uncommitted fix.
The eight changed runtime/test files matched the tested clone byte-for-byte.
SHA-256 of sorted repository-path/NUL/content/NUL entries:
`0edc026a81bb8ea5d421de70d51d2b934c4bfe48ebc3946e44fad97e2a82675b`.
Tests ran on `andreG7linux`, Ruby 4.0.9 / Rails 8.1.4 / PostgreSQL, in an isolated
clone `/tmp/trr-card-fixes` with a fresh schema-only `trr_card_dates_test` database.
No production data, paid AI, real email or production SSH was used.

`/tmp/trr-card-run` sets `RAILS_ENV=test`,
`DATABASE_URL=postgresql:///trr_card_dates_test`, `PARALLEL_WORKERS=1`,
`CHROME_BIN=/usr/bin/chromium`, temporary Bundler/RuboCop homes, and the installed
bundle matching the baseline lockfile. It unsets named database URLs and
Loops/OpenAI keys. Ordinary and browser suites ran serially.

`MeetingCardDatesTest` crosses actual PostgreSQL queries and HTTP/view rendering
without stubbing time-zone casting. Five explicit UTC fixtures cover standard
time at midnight, daylight time after midnight, month and year rollover, and a
daytime control. Each verifies identified top/Wire/Topics/search/committee cards
against the independent meeting detail and Next Up display and confirms the
stored instant is unchanged. Additional cases exercise older-topic HTML/Turbo
append cards and gated anonymous/member cards.

`MeetingCardDatesJourneysTest` uses real Chrome, JavaScript/Turbo and visible
links/search controls: home → topic Coming Up → meeting → topic search → topic
and refresh. The Wire journey uses the long joint committee name with/without a
synthetic attached image, checks dates, one text line for the CTA, containment,
non-overlap and page width at 1440/390/320px, clicks "Full story", and verifies
the destination's local day after refresh. Screenshots at those widths were
visually inspected. The image is a synthetic one-pixel fixture, not a review of
production artwork.

| Command after `/tmp/trr-card-run` | Result |
| --- | --- |
| `bin/rails test test/controllers/meeting_card_dates_test.rb --verbose` | 7 runs, 182 assertions; no failures/errors/skips |
| `bin/rails test test/system/meeting_card_dates_journeys_test.rb --verbose` | 2 runs, 58 assertions; no failures/errors/skips |
| `bin/rails test test/helpers/meetings_helper_test.rb test/controllers/home_controller_test.rb test/controllers/topics_controller_test.rb test/controllers/committees_controller_test.rb test/controllers/home_gating_test.rb test/controllers/topics_card_gating_test.rb test/controllers/meeting_card_dates_test.rb` | 145 runs, 761 assertions; no failures/errors/skips |
| `bin/rails test:system` after restoring both faults | 22 runs, 759 assertions; no failures/errors/skips |
| `bin/rubocop` | 627 files; no offenses |

`git diff --check` passed; 107 local links/anchors in the updated application-map
documents resolved. The simplify review retained the small shared formatter and
existing queries; no additional abstraction or timestamp storage change was needed.

The browser runner emitted existing Selenium cache/ChromeDriver version warnings;
these did not prevent executing the assertions. No new CI result or production
verification is claimed for this uncommitted change.

## Demonstrated defect detection

The initial pre-fix HTTP suite ran seven tests: six failed on wrong date labels,
the daytime control passed, and no errors/skips occurred. After the clean
7/182 and 2/58 baselines above, bounded faults were applied only in the isolated
clone:

| Fault | Command after wrapper | Observed intended failure |
| --- | --- | --- |
| Remove `in_time_zone` from the shared formatter | `bin/rails test test/controllers/meeting_card_dates_test.rb --verbose` | 7 runs, 46 assertions, 6 failures, 0 errors/skips; e.g. Nov 3 instead of Nov 2 and Jan 1 instead of Dec 31 |
| Restore pre-fix Wire CSS while retaining the date fix | `bin/rails test test/system/meeting_card_dates_journeys_test.rb --verbose -n /wire_dates/` | 1 run, 7 assertions, 1 failure, 0 errors/skips: "Full story wrapped at 1440px", two lines instead of one |

Both faults were restored before the final regression runs. The date faults
demonstrate calendar-boundary detection; the browser fault independently proves
the layout assertion catches the actual wrapping defect. Existing access tests
were retained rather than replaced by the date assertions. These checks cover
the listed variants and do not establish complete coverage of every role,
browser, public API or resident workflow.
