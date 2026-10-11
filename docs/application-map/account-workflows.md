# Account and authentication workflows

All entries are **documented, runtime unverified** at the [baseline](README.md).
Expectations derive from the [passwordless design](../superpowers/specs/2026-07-23-passwordless-auth-and-applications-design.md),
[session design](../superpowers/specs/2026-07-25-session-and-reauthentication-hardening-design.md),
[membership/access requirements](../DEVELOPMENT_PLAN.md), and
[API contract](../read-only-api.md). The sign-out acceptance contract also comes
directly from the user's behavioral-validation brief. Source observations never
establish that these outcomes actually occur in a browser.

## AUTH-01 — Request a sign-in email (P0)

- **Start / data:** anonymous visitor; test separately with an active, pending,
  rejected, disabled, unknown, and malformed address; consider source/address throttles.
- **Action:** open Sign in, enter email, submit the displayed form.
- **Required state / visible outcome:** general browser status/message/redirect
  does not disclose account eligibility. Eligible owner receives an absolute
  single-use link; pending owner receives review guidance; other deliverable
  addresses receive application guidance. Requesting a link does not sign in.
- **Next:** protected Account still requires authentication; follow AUTH-02 for
  the emailed link. A failed delivery must not consume the address retry window.
- **Failures to distinguish:** delivery unavailable, IP limit, address cooldown,
  malformed input; no account-specific browser response or usable token in HTML.
- **Observed:** [SessionsController](../../app/controllers/sessions_controller.rb)
  POST `/session`; [TransactionalEmail](../../app/services/transactional_email.rb),
  [SignInAttempt](../../app/models/sign_in_attempt.rb). Real mailbox delivery is unverified.

## AUTH-02 — Confirm a magic link and return to the task (P0)

- **Start / data:** eligible active account, unused sign-in token and its expiry;
  separately test a stored safe return destination and no destination.
- **Action:** follow emailed link (GET), then activate the confirmation form (POST).
- **Required state / visible outcome:** GET alone grants no session. POST consumes
  the token once and grants member access; land on the safe requested destination
  or What's New. Authentication navigation shows Account/Sign out.
- **Next:** load own Profile and gated reporting; replaying the same token fails.
  A link opened in another browser authenticates that browser, not the original one.
- **Failures to distinguish:** used/expired/invalid token, inactive owner, unsafe
  external return target. The design's dedicated expired-approval replacement
  journey is not represented by the current page; see V-07.
- **Observed:** GET/POST `/session/magic_link`,
  [MagicLink](../../app/models/magic_link.rb),
  [Authentication](../../app/controllers/concerns/authentication.rb),
  [confirmation view](../../app/views/sessions/magic_link.html.erb).

## AUTH-03 — Sign in with a passkey (P0)

- **Start / data:** active account with a registered credential, secure browser
  origin and authenticator; no current member session required.
- **Action:** Sign in → passkey button → browser credential selection/verification.
- **Required state / visible outcome:** a valid owned credential signs in and
  returns to the intended safe destination. User verification is required.
- **Next:** member pages work; a new session starts a fresh reauthentication window.
- **Failures to distinguish:** cancellation, insecure/unsupported browser,
  unknown credential, inactive owner, missing/replayed challenge, request limit;
  failures do not grant a session and email sign-in remains available.
- **Observed:** [PasskeysController](../../app/controllers/passkeys_controller.rb)
  authentication options/authentication JSON; [WebAuthn verification](../../app/controllers/concerns/webauthn_verification.rb)
  and [browser controller](../../app/javascript/controllers/passkey_controller.js).

## AUTH-04 — Sign out from either application shell (P0)

- **Start / data:** active signed-in member or eligible admin; first prove own
  Account/protected access and full gated reporting actually work.
- **Action:** click the displayed **Sign out** in the public shell or **Sign Out**
  in the admin sidebar. Exercise both visible controls, including mobile admin navigation.
- **Required state / visible outcome:** request succeeds without a 500;
  authenticated session ends; homepage renders anonymous navigation and the
  appropriate access-mode tier. A success redirect alone is insufficient.
- **Next:** reload and visit Profile, API-key settings and Admin; they require
  sign-in. A retained copy of the old cookie must not restore that session.
  Signing out one session is not the revoke-all-sessions operation.
- **Failures to detect:** wrong browser HTTP method, CSRF failure, deletion failure,
  cookie/Current leakage, stale privileged content reused after navigation.
- **Observed:** both [public layout](../../app/views/layouts/application.html.erb)
  and [admin sidebar](../../app/views/admin/shared/_sidebar.html.erb) use Turbo
  DELETE `/session`; [SessionsController#destroy](../../app/controllers/sessions_controller.rb)
  clears the server session/cookie and redirects with 303. This was not clicked.

## AUTH-05 — Lose session eligibility while browsing (P0)

- **Start / data:** established session; separate variants for 60-day inactivity,
  one-year lifetime, removed row, disabled/rejected/pending owner, admin role removal.
- **Action:** expire/revoke/change authority in an isolated environment, then make
  the next ordinary request with the existing browser cookie.
- **Required state / visible outcome:** invalid sessions no longer grant member
  access; protected pages request sign-in. Role removal leaves an active member
  session but removes Admin authority. Context changes alone do not sign out.
- **Next:** repeated requests remain denied; an eligible owner can sign in anew.
  Re-enable behavior is distinct from revocation; API eligibility is AUTH-15.
- **Failures to detect:** allowing inactive accounts, refreshing beyond hard
  expiry, denying ordinary reading merely due to a new network, cached authority.
- **Observed:** [Session](../../app/models/session.rb),
  [Authentication](../../app/controllers/concerns/authentication.rb),
  [admin boundary](../../app/controllers/admin/base_controller.rb).

## AUTH-06 — Start an application and verify email (P1)

- **Start / data:** unknown deliverable address; compare existing email-pending,
  submitted, active, rejected and disabled account states without disclosing them.
- **Action:** Apply → submit email → follow the emailed application URL.
- **Required state / visible outcome:** eligible application starter becomes a
  pending disabled account with an email-pending application. Correct token opens
  the form; possessing an application URL is not a member session.
- **Next:** complete AUTH-07. Repeated starts must not silently reopen a rejection
  or duplicate an already submitted application.
- **Failures to distinguish:** invalid address/token/purpose, wrong application
  identity, unavailable delivery, throttled starts; no applicant data on a generic confirmation.
- **Observed:** [ApplicationsController](../../app/controllers/applications_controller.rb)
  new/create/edit; application-purpose [MagicLink](../../app/models/magic_link.rb).
  Form GET does not consume the application token.

## AUTH-07 — Submit and correct an application (P1)

- **Start / data:** valid email-pending application/token; required first/last
  name, street, city, state; optional phone, secure Facebook URL and notes.
- **Action:** submit incomplete/invalid form, correct it, then submit valid details.
- **Required state / visible outcome:** invalid form shows usable errors and can
  be corrected without losing the token. Success records the submitted application,
  consumes the token, queues admin notification, and shows a reloadable submitted
  confirmation without private applicant information. Account remains disabled.
- **Next:** reopening/resubmitting the consumed link cannot alter the submission;
  admin can review it; applicant cannot sign in before approval.
- **Failures to detect:** lost fields/token on validation, partial writes,
  request-supplied IP replacing server-observed IP, duplicate submission race.
- **Observed:** [ApplicationsController#update](../../app/controllers/applications_controller.rb),
  [application model](../../app/models/membership_application.rb),
  [edit form](../../app/views/applications/edit.html.erb),
  [notification job](../../app/jobs/admin_application_notification_job.rb). Notification timing needs V-08.

## AUTH-08 — Receive a membership decision and first access (P1)

- **Start / data:** email-pending or submitted application; eligible administrator;
  applicant has no authenticated session.
- **Action:** admin reviews and approves or denies with a reason (ADM-02).
- **Required state / visible outcome:** approval activates account and sends a
  sign-in link; completing AUTH-02 permits the first full member read. Denial
  records reviewer/reason, denies login and sends the exact denial reason.
- **Next:** rejected address cannot silently reapply; reviewing before completed
  submission must still produce a coherent decision/history.
- **Failures to distinguish:** missing reason, concurrent review, delivery failure,
  rollback/compensation, expired approval link; never treat an enqueued email as receipt.
- **Observed:** [MembershipApplicationDecision](../../app/services/admin/membership_application_decision.rb)
  locks/updates records and compensates on delivery errors. Browser handling of
  all provider failures was not demonstrated; V-07/V-08 remain open.

## AUTH-09 — Read own account profile (P1)

- **Start / data:** active member with or without historical application records.
- **Action:** Account → Profile, then use Account tabs.
- **Required state / visible outcome:** own normalized account/profile/application
  data only; page is read-only and does not imply editable personal details.
- **Next:** Security and API keys are reachable; a different account cannot select
  or obtain this account's private profile by changing parameters.
- **Failures to detect:** wrong application's details, nil-history crash,
  unauthorized profile visibility, apparent edit controls without a save path.
- **Observed:** [ProfileController](../../app/controllers/settings/profile_controller.rb)
  scopes to `current_user` and selects the latest application;
  [Profile view](../../app/views/settings/profile/show.html.erb).

## AUTH-10 — Add, rename and remove own passkeys (P0)

- **Start / data:** active browser session; add/remove require recent identity
  proof and strict accepted context. Include another owner's credential and the
  last usable administrator's only passkey.
- **Action:** Security → Add → complete device ceremony; rename → Save; Remove
  → confirm. Perform separate assertions for each action.
- **Required state / visible outcome:** credential belongs to current user; name
  persists after reload; removed credential cannot sign in; someone else's cannot
  be changed. Preserve at least one usable administrator. Admins cannot manage
  another user's passkeys from User Accounts.
- **Next:** new credential supports AUTH-03; admin without passkey becomes eligible
  after setup. Locked add/remove offers Confirm it's you, then returns usefully.
- **Failures to distinguish:** device cancellation, failed challenge/verification,
  stale context/freshness, limits, invalid nickname, last-admin refusal; no partial credential.
- **Observed:** [PasskeysController](../../app/controllers/passkeys_controller.rb),
  [credential model](../../app/models/passkey_credential.rb),
  [Security view](../../app/views/settings/security/show.html.erb). Rename has no
  additional step-up gate. Known-context UI/controller alignment needs V-09.

## AUTH-11 — Dismiss a passkey reminder (P2)

- **Start / data:** active non-admin account without a passkey and no current dismissal.
- **Action:** upper-right reminder → Not now.
- **Required state / visible outcome:** optional reminder disappears for about
  one week across that user's devices; ordinary email-authenticated reading still works.
- **Next:** reminder can return after suppression expires; adding a credential
  removes the need for the reminder. Admin setup requirements do not become optional.
- **Failures to detect:** only hiding the current DOM, suppressing another user,
  reminder reappearing immediately, suppressing required admin setup.
- **Observed:** [public layout](../../app/views/layouts/application.html.erb),
  [PasskeyPromptsController](../../app/controllers/settings/passkey_prompts_controller.rb),
  [User](../../app/models/user.rb) stores dismissal time.

## AUTH-12 — Reauthenticate and resume a sensitive task (P0)

- **Start / data:** valid session whose action lacks freshness/context; distinguish
  admin tolerant gate from strict credential/account mutations and known contexts.
- **Action:** follow challenge; use own passkey or request/confirm ordinary sign-in email.
- **Required state / visible outcome:** proof authorizes the appropriate action
  without a redirect loop. Passkey updates the existing session's context/time;
  email authenticates the browser opening it. JSON denials are 403, not HTML redirects.
- **Next:** return to safe retrieval/referrer and deliberately retry the mutation;
  do not replay a destructive POST automatically. A new unfamiliar context can
  need proof again. Email opened elsewhere does not reauthenticate the original browser.
- **Failures to distinguish:** other user's credential, failed/cancelled ceremony,
  unavailable email, rate limit; passkey failures cannot consume the email fallback budget.
- **Observed:** [Reauthentication](../../app/controllers/concerns/reauthentication.rb),
  [challenge controller](../../app/controllers/reauthentications_controller.rb),
  [KnownContext](../../app/models/known_context.rb), [Session](../../app/models/session.rb).

## AUTH-13 — Issue and save a personal API key (P0)

- **Start / data:** active member browser session with fresh identity proof and
  accepted strict context; name and expiry (30/90/180 days).
- **Action:** Account → API keys → Create → submit → Copy → Done.
- **Required state / visible outcome:** full secret appears once and clipboard
  contains it; reload/list/admin views show metadata only. Responses cannot be
  cached. Issuance is audited without secret/digest exposure.
- **Next:** use header credential for RES-13; it cannot authenticate browser
  settings/Admin or write content. Admin-owned keys have the same fixed scope.
- **Failures to distinguish:** invalid name/expiry, stale proof/context, creation
  limit, clipboard denial; no secret in URLs, follow-up HTML, logs or admin metadata.
- **Observed:** [ApiKeysController](../../app/controllers/settings/api_keys_controller.rb),
  [one-time view](../../app/views/settings/api_keys/created.html.erb),
  [copy controller](../../app/javascript/controllers/api_key_copy_controller.js),
  [ApiAccessToken](../../app/models/api_access_token.rb).

## AUTH-14 — Revoke one or all personal API keys (P0)

- **Start / data:** current user's keys, including expired/revoked rows; another
  owner's key; first prove a chosen active key can read the API.
- **Action:** Revoke key or Revoke all keys → confirm in browser.
- **Required state / visible outcome:** own selected/all keys become revoked;
  metadata reflects it; audit survives. Other user's credentials are unaffected.
- **Next:** retained secret now receives 401 on next request; existing browser
  session still works. Reload cannot recover the revoked secret.
- **Failures to detect:** unauthorized ID, partial bulk revocation, API cache
  reuse, treating a label change as revocation.
- **Observed:** [ApiKeysController](../../app/controllers/settings/api_keys_controller.rb)
  destroy/revoke_all are owner-scoped; [API authentication](../../app/controllers/api/base_controller.rb).

## AUTH-15 — Lose and restore API-owner eligibility (P0)

- **Start / data:** working key; account disabled, rejected or deleted; separately
  key expired/revoked and account restored to active.
- **Action:** account eligibility changes (ADM-02/03/04); client makes its next request.
- **Required state / visible outcome:** ineligible owner cannot read; deletion
  removes keys. Restoring eligibility can reactivate otherwise valid keys;
  expiry/revocation still deny. Browser logout alone does not revoke a key.
- **Next:** choose explicit revocation before restoring an account if credentials
  should stay unusable; client can inspect eligibility only through normal owner access.
- **Failures to detect:** cached account status, revoked key resurrection,
  administrator-owned key unexpectedly granting administrative permissions.
- **Observed:** [ApiAccessToken](../../app/models/api_access_token.rb),
  [User](../../app/models/user.rb), [API contract](../read-only-api.md).
