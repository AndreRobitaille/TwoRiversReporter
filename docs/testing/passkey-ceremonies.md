# Passkey verification and approved context policy

The secure-browser journeys use Selenium's documented
[virtual authenticator](https://www.selenium.dev/documentation/webdriver/interactions/virtual_authenticator/):
CTAP2, internal transport, resident credentials and user verification/consent.
Hardware, biometrics and consent are simulated. Browser WebAuthn calls, CSRF,
challenge creation, signatures, WebAuthn library verification, owned database
credentials, session cookies, redirects and later access are real. Keys are
created by the browser; no credential is injected into the authenticator.

Tests use a secure `http://localhost` origin and assert `window.isSecureContext`.
Only this test class temporarily sets the RP origin to its actual server port
and RP ID to localhost, restoring both and removing the authenticator afterward.
Production configuration and authentication predicates are unchanged.

`PasskeyCeremonyJourneysTest` registers through the visible control, compares
the stored ID with the authenticator ID and owner, logs out, signs back in with
that credential, checks the new session/sign counter, and removes the key.
A second journey challenges stale proof, performs real step-up and checks the
next task. It also makes proof stale after an allowed page was rendered: the
actual DELETE challenges, step-up returns to the referring Security GET, the
credential survives that return, and the deliberate repeated DELETE succeeds.

`PasskeyManagementMatrixTest` compares rendered controls and direct registration
options/registration/removal for the same persisted session state:

| State | Current page | Current add/remove endpoint |
| --- | --- | --- |
| Fresh matching anchor | Available | Allowed |
| Fresh known different pair | Challenge | Allowed |
| Fresh unknown pair | Challenge | Denied |
| Stale matching anchor | Challenge | Denied |
| Stale known different pair | Challenge | Denied |

Andre approved preserving this current matrix on October 11, 2026 in response
to #175, explaining that overly restrictive smart authentication had been
relaxed. The endpoint's remembered-pair allowance remains additive; the page
continues to request step-up before offering controls away from the anchor.
The July 25 specification now records this distinction. No authentication
predicate changed, and freshness and ownership remain independent requirements.
For allowed registration, the matrix probes real options and malformed-payload
rejection; full successful ceremonies are covered by the separate browser tests.
Foreign IDs, last usable admin protection, HTML challenges and JSON 403 preserve
credential attributes and audit state on rejection. Matrix credentials/sessions
are synthetic fixtures and do not independently establish a ceremony.

The existing registration/challenge test was strengthened. Its explicit Cookie
header discarded the challenge cookie between requests; its verifier accepted
nil, and retaining the challenge passed undetected. A persistent client now
proves the named challenge reaches verification and a second distinct
registration receives 422 with unchanged stored credentials. The same retained
challenge fault now fails the intended assertion. Parsing/verification are
still mocked in that narrow test; the browser journeys supply real signatures.

A new browser selector initially matched remembered-network rows as well as
credential rows. It is now scoped to the passkey section and checks the actual
persisted quantity. Omitting persistence fails the intended visible-credential
assertion, with no incidental missing-record exception. Separate restored faults
also detect a missing page context predicate and missing endpoint freshness.

```sh
bin/rails test test/controllers/passkeys_controller_test.rb \
  test/controllers/passkey_management_matrix_test.rb \
  test/controllers/settings/security_controller_test.rb
bin/rails test:system
bin/rubocop
bin/ci
```
