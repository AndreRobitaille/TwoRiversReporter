# Browser sign-in and logout verification

The small Rails system suite uses Capybara, Selenium and headless Chrome with
real JavaScript/Turbo, CSRF protection, forms, HTTP requests and browser cookies.
It runs separately from the application suite: `bin/rails test` deliberately
excludes system tests. Both local `bin/ci` and GitHub CI invoke
`bin/rails test:system` explicitly; browser failures fail the CI job.

## Run locally

Install the bundle and Chrome/Chromium with a matching chromedriver. Selenium
can locate installed browsers; set `CHROME_BIN` if its default is unsuitable.
Confirm the test database is local/disposable and no inherited `DATABASE_URL`
or named database URL points at production. A fresh test database should load
the schema without application seeds: `RAILS_ENV=test bin/rails db:create
db:schema:load`. Application seeds include canonical committees that conflict
with tests which create their own records.

```sh
bin/rails test
CHROME_BIN=/usr/bin/chromium PARALLEL_WORKERS=1 bin/rails test:system
bin/rails test test/controllers/session_eligibility_journeys_test.rb
bin/ci
```

The harness binds Puma to `0.0.0.0` and visits a `localhost` origin. Local email
URLs are absolute and point to that same browser server's actual port. Test
configuration, URL options and delivery capture are restored after each test.
Failures produce screenshots in `tmp/screenshots`; GitHub retains them as a
failure artifact. Application and browser suites run serially against the test
database.

GitHub's downloaded Chrome for Testing uses the runner's installed Chrome
setuid sandbox helper through `CHROME_DEVEL_SANDBOX`. The workflow checks that
helper and smoke-tests headless startup before running the journeys. This follows
[Chromium's sandbox guidance](https://chromium.googlesource.com/chromium/src/+/main/docs/security/apparmor-userns-restrictions.md)
for downloaded builds on Ubuntu; the browser sandbox stays enabled.

## What these tests prove

`AuthenticationJourneysTest` starts anonymous, submits the sign-in form,
captures the actual `TransactionalEmail::Message`, and opens its usable URL.
GET leaves both the token and authentication state untouched; confirmation POST
creates an own-account session. Both public and eligible-admin Sign out controls
then exercise Turbo DELETE. The tests require the public destination, deleted
server session, cleared authentication cookie, denied later protected access,
and denied replay of the cookie that worked before logout.

`SessionEligibilityJourneysTest` proves own-account access before revocation,
idle/absolute expiry, disabling, pending or rejected status. The next protected
request must remove invalid state, and replay must remain denied.

`ResidentNavigationJourneysTest` follows the rendered homepage topic and meeting
cards and public navigation in open mode, gated anonymous mode and gated member
mode. These destination checks preserve current navigation; they do not settle
the unresolved anonymous source-link, roster or teaser policy in #172.

Only the final email transport is captured. Token creation, recipient/URL
construction, GET/POST consumption, database persistence and session access stay
real. No Loops delivery occurs. The eligible-admin credential is synthetic and
establishes eligibility only; these tests do not establish WebAuthn registration
or authentication ceremony coverage. Paid AI providers are not part of these
journeys.

Related acceptance and evidence: [#169](https://github.com/AndreRobitaille/TwoRiversReporter/issues/169)
and [#168](https://github.com/AndreRobitaille/TwoRiversReporter/issues/168).
