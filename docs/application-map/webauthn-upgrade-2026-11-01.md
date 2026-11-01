# WebAuthn 3.5.0 compatibility review — November 1, 2026

No upgrade regression was found in the exercised account workflows. PR #226
includes the subsequent malformed-signature correction described below. No
deployment was requested or performed.

## Revisions and requirements

The three authorized merges produced master
`0e0fa0da1484fd7032faeeaf6ef3b13dbe5191fb`. Its GitHub
[CI](https://github.com/AndreRobitaille/TwoRiversReporter/actions/runs/41318452875)
and [runtime image](https://github.com/AndreRobitaille/TwoRiversReporter/actions/runs/41318452908)
checks passed. An intermediate #223 audit failure identified Addressable
advisories; #224 updated Addressable to 2.9.2 and subsequent master checks passed.

The candidate is that master revision plus the exact two-line WebAuthn version
and checksum update from [PR #226](https://github.com/AndreRobitaille/TwoRiversReporter/pull/226),
head `5bcb7dc940b12d2d5c51eb9b2c9e37c8ff27538f`.
Other merged dependency versions were retained. Candidate patch SHA-256:
`27c891d98ab38468f151b96c60953e7c0d2f9bd03b1039aa758bb382e0307e5b`.
The PR's original five checks passed; the combined candidate was tested locally
without rebasing or pushing the PR.

Acceptance comes from the [passwordless design](../superpowers/specs/2026-07-23-passwordless-auth-and-applications-design.md),
[session design](../superpowers/specs/2026-07-25-session-and-reauthentication-hardening-design.md)
and [approved passkey matrix](policy-matrices.md#passkey-page-and-endpoints-175).
Affected workflows are AUTH-03 sign-in, AUTH-10 owned credential management and
AUTH-12 step-up. Active owners must retain access, valid device and synced
credentials must verify, failed proof must not grant a session or mutate stored
credentials, and step-up must update the existing owner's session.

The [upstream changelog](https://github.com/cedarcode/webauthn-ruby/blob/v3.5.0/CHANGELOG.md)
adds backup-flag and credential-ID-length checks and changes the default options
timeout from 120 to 300 seconds. The new errors inherit from `WebAuthn::Error`,
which the app already handles. Source inspection found no app/test use of the
removed TokenBinding APIs. Cross-origin verification is opt-in and remains
disabled by default; this review does not claim a new cross-origin policy.
Public-key storage and sign-counter handling require no migration or credential
re-enrollment in the exercised cases.

[RubyGems records October 22, 2026](https://rubygems.org/gems/webauthn/versions/3.5.0)
as the release date. The previously established 14-day dependency-age guidance
reaches its threshold on November 5. The owner explicitly authorized this
earlier merge once the fix is included and CI passes.

## Local execution

Tests ran on `andreG7linux`, Ruby 4.0.9 / Rails 8.1.4, in an isolated clone at
`/tmp/trr-pr226-review`. A fresh local PostgreSQL database,
`trr_pr226_review_test`, was created from the schema without application seeds.
The original checkout and its existing `vendor/bundle` were preserved. The
isolated bundle was copied, then installed serially with `--jobs 1`.

Every Rails command below used `/tmp/trr-pr226-run`, which sets `RAILS_ENV=test`,
`DATABASE_URL=postgresql:///trr_pr226_review_test`, `PARALLEL_WORKERS=1` and
`CHROME_BIN=/usr/bin/chromium`; unsets inherited named database URLs and
Loops/OpenAI keys; and uses a temporary Bundler home. Application and browser
suites ran serially. Browser journeys use secure localhost origins, real
JavaScript/Turbo/CSRF/cookies and Selenium's virtual CTAP2 authenticator.

| Command after the wrapper | Result |
| --- | --- |
| `bin/rails test test/controllers/passkeys_controller_test.rb test/controllers/passkey_management_matrix_test.rb test/controllers/reauthentications_controller_test.rb test/controllers/fresh_reauthentication_test.rb test/models/passkey_credential_test.rb` on 3.4.3 | 47 runs, 208 assertions; no failures/errors/skips |
| `bin/rails test:system test/system/passkey_ceremony_journeys_test.rb` on 3.4.3 | Runner executed all 20 browser journeys, 701 assertions; no failures/errors/skips |
| `bin/rails test test/integration/webauthn_upgrade_review_test.rb` on 3.5.0 | 17 temporary probes, 195 assertions; no failures/errors/skips |
| `bin/rails test` on 3.5.0 | 2,161 runs including the 17 probes, 13,317 assertions; no failures/errors, one existing skip |
| `bin/rails test:system` on 3.5.0 | 20 journeys, 701 assertions; no failures/errors/skips |
| `bin/rubocop` | 625 files, no offenses |
| `env BUNDLER_AUDIT_DB=/tmp/trr-pr226-advisories bin/bundler-audit check --update` | No known vulnerabilities; advisory DB `f49697a0be9a6b5affa265cee47fb54739117239` |

The sole skip was independently confirmed with
`bin/rails test test/models/prompt_run_test.rb --verbose`:
`PromptRunTest#test_polymorphic_source_association`, "No meeting fixture available."
That command ran nine tests, 17 assertions, one skip, no failures/errors.

The temporary probes exercise actual HTTP dispatch, WebAuthn cryptographic
verification, persistence and subsequent protected requests. They cover a
synthetic 3.4.3-generated public key authenticating on 3.5.0; BE/BS states 0/0,
1/0 and 1/1 through registration, sign-in and step-up; bad challenges, missing
user verification, foreign origin/RP, inconsistent backup flags, overlong ID,
invalid signed proof, replay, inactive owner and valid foreign-owner step-up.
Browser journeys separately exercise visible Add, Sign in, Remove and stale
proof recovery, including persisted ownership/counters and later account access.

## Demonstrated defect detection

After the clean candidate baseline, one bounded fault at a time was applied in
the isolated clone/bundle. Each intended assertion failed with zero test errors:

| Fault | Selection in the temporary probe file | Result |
| --- | --- | --- |
| Disable sign-in user-verification enforcement | `/test_sign_in_rejects_missing_user_verification/` | One assertion failure: accepted response instead of 401 |
| Make the gem's backup-flag validator always accept | `/inconsistent_backup_flags/` | Two assertion failures: registration/sign-in accepted instead of 422/401 |
| Make the gem's credential-ID-length validator always accept | `/overlong_credential_ID/` | One assertion failure: registration accepted instead of 422 |

All faults were restored. Both modified gem files were compared byte-for-byte
with upstream tag `v3.5.0`; the app verification concern has no diff. The full
17-probe suite passed again (195 assertions), followed by the explicit discovered
browser command `bin/rails test test/system/passkey_ceremony_journeys_test.rb --verbose`:
both named journeys ran, 100 assertions, no failures/errors/skips.

Temporary probes, fixture generator, bounded-fault script and raw logs are under
`/tmp/trr-pr226-review/test/integration/webauthn_upgrade_review_test.rb`,
`/tmp/trr-pr226-legacy.rb`, `/tmp/trr-pr226-faults.py` and
`/tmp/trr-pr226-evidence/`. These are local review artifacts, not committed tests;
the synthetic legacy key material is not production credential data.

## Existing error path and limits

A separate malformed ECDSA signature probe raised
`OpenSSL::PKey::PKeyError: EVP_DigestVerify` through
`WebauthnVerification#verified_get_credential` on both 3.4.3 and 3.5.0. The app
rescues `WebAuthn::Error`, so this malformed-input exception escapes that handler.
The expected graceful-denial probe produced one error on each version. The
initial review left this existing gap open; the follow-up below corrects it.
A well-formed but cryptographically invalid ECDSA signature was separately
rejected with 401 without changing the credential or creating a session.

The browser/device authenticator, biometric verification and consent are
simulated. Actual Apple/Android/1Password/hardware credentials, production
accounts, live email and production deployment were not exercised. Selenium
reported a driver-version detection warning; all browser runs completed. These
results establish the exercised boundaries, not every device/provider variant.

## Follow-up: malformed-signature correction

The owner subsequently requested correcting this error before merging #226.
The correction in
[WebauthnVerification](../../app/controllers/concerns/webauthn_verification.rb)
catches the specific `OpenSSL::PKey::PKeyError` alongside `WebAuthn::Error` and
returns the existing 401 response for failed proof. Both sign-in and step-up use
this verifier. No general exception handler or dependency change was added.

[PasskeySignatureErrorsTest](../../test/controllers/passkey_signature_errors_test.rb)
adds four permanent HTTP regression cases: invalid DER and truncated DER, each
through sign-in and step-up. They first prove valid signed proof works. They
then require 401, unchanged stored credential/counter/last-used fields, no new
session or refreshed step-up, denial of the appropriate later request, consumption
of the failed challenge, and successful recovery using a fresh challenge. A
failed step-up preserves ordinary account access while credential management
remains forbidden. WebAuthn signature verification and database state are real;
the authenticator is simulated with the gem's `FakeClient`.

The tests reproduced four native OpenSSL errors before the fix on 3.5.0. With
the fix they passed on both 3.4.3 and 3.5.0: four runs, 112 assertions, no
failures/errors/skips per version. For representative defect detection after
the passing baseline, the isolated verifier was changed to return the credential
on `OpenSSL::PKey::PKeyError`, accepting malformed proof. All four intended 401
assertions failed (four runs, 36 assertions, four failures, zero errors/skips).
The fault was restored before the following green verification on each version:

```sh
/tmp/trr-pr226-run bin/rails test \
  test/controllers/passkey_signature_errors_test.rb \
  test/controllers/passkeys_controller_test.rb \
  test/controllers/passkey_management_matrix_test.rb \
  test/controllers/reauthentications_controller_test.rb \
  test/controllers/fresh_reauthentication_test.rb \
  test/models/passkey_credential_test.rb
/tmp/trr-pr226-run bin/rails test \
  test/system/passkey_ceremony_journeys_test.rb --verbose
```

The 3.4.3 commands insert
`env BUNDLE_GEMFILE=/tmp/trr-pr226-review/Gemfile.baseline` after the wrapper;
that Gemfile retains the merged dependencies with WebAuthn 3.4.3. Focused tests
passed with 51 runs / 320 assertions per version. Both named native browser
journeys passed with two runs / 100 assertions per version. There were no
failures, errors or skips. Ruby syntax checks passed for the concern and new test.
`bin/rubocop` also passed with 626 files inspected and no offenses, using a
temporary `RUBOCOP_CACHE_ROOT`.
The earlier full application/browser suite results above precede this fix;
these focused commands are the subsequent correction evidence. Raw logs use
the `signature-` prefix in `/tmp/trr-pr226-evidence/`.

Local verification began with primary checkout
`1d22bc45245dfaaeacc372bca4b87f3de9317990` plus the fix/tests/docs.
Execution used the existing isolated review clone at
merged master `0e0fa0da1484fd7032faeeaf6ef3b13dbe5191fb` with this same fix and,
for the 3.5.0 runs, the #226 lockfile patch. Publication and final CI are tracked
on [PR #226](https://github.com/AndreRobitaille/TwoRiversReporter/pull/226).
No production deployment is part of this change.
