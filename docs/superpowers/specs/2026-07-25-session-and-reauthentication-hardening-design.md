# Session and Reauthentication Hardening Design

## Goal

Shorten session lifetime, and make a change of network or browser mean something. Today a
session survives 180 days of inactivity, rolls forward indefinitely on use, and records
`ip_address` and `user_agent` at sign-in without ever comparing them to anything. A six-month-old
session can hard-delete a user account with no challenge.

This design adds step-up reauthentication, driven by a session context that is finally compared,
without ever signing anyone out for changing networks.

## Current Context

Authentication is passwordless (`docs/superpowers/specs/2026-07-23-passwordless-auth-and-applications-design.md`).
Two ways in: a 15-minute single-use `MagicLink` delivered through Loops, and `PasskeyCredential`
over WebAuthn. `Admin::BaseController` already requires admin, `active_for_authentication?`, and at
least one passkey — so **every admin necessarily has a passkey**, which is what makes cheap
one-tap step-up viable in the admin area.

The site is live at `https://tworiversmatters.com` with real members. The owner's admin account is
the only route into the admin area, and no UI exists to create the first admin back. Lockout is the
primary risk this design is shaped around.

## The Central Decision

**Session validity and authorization to act are decoupled.**

A changed IP or device never destroys a session. It marks the session's recorded context as no
longer matching, and *that* is what forces reauthentication before a sensitive action. A phone
hopping between cell towers costs the user nothing until they try to do something dangerous.

This is what makes IP-based reauthentication workable on mobile at all. The alternative —
invalidating sessions on IP change — signs mobile users out several times a day and is the highest
lockout risk available.

## Session Lifetime

`Session` gains an absolute cap alongside a shortened rolling limit:

| Constant | Before | After |
|---|---|---|
| `INACTIVITY_LIMIT` | `180.days` | `60.days` |
| `ABSOLUTE_LIFETIME` | — | `1.year` (from `created_at`) |
| `TOUCH_INTERVAL` | `15.minutes` | unchanged |

`inactive?` keeps its current meaning. A new `beyond_absolute_lifetime?` compares `created_at`. A
new `expired?` ORs the two, and `Authentication#resume_session` calls `expired?` where it currently
calls `inactive?`.

The rolling limit stays rolling: active use keeps a session alive up to the absolute cap. The
absolute cap has no effect on deploy — passwordless auth shipped 2026-07-23, so no session is
older than a few days. It begins to matter in July 2027, when it will sign everyone out once and
require a magic link.

## Session Context

### New columns on `sessions`

| Column | Type | Purpose |
|---|---|---|
| `ip_prefix` | string | Network prefix the session was last verified from |
| `device_fingerprint` | string | Browser family and platform, version discarded |
| `reauthenticated_at` | datetime | Last successful step-up, or sign-in |

The existing `ip_address` and `user_agent` columns stay. They are displayed on `/admin/users/:id`
and are the source data for the migration backfill.

### Value objects

Three small classes in `app/models/`, each testable without a request or a database row.

**`NetworkPrefix.for(ip_string)`** — masks IPv4 to /24 and IPv6 to /48, returning a canonical
string such as `"203.0.113.0/24"`. Blank or unparseable input returns `nil`. Implemented with
`IPAddr` from the standard library; no GeoIP database, no ASN lookup, no new infrastructure.

A /24 absorbs most carrier and wifi churn inside one network while still catching a cookie replayed
from a different city or a different provider. /48 is the IPv6 equivalent: subscriber allocations
are typically /48 or /56, so /48 is the coarser and therefore more forgiving choice.

**`DeviceFingerprint.for(user_agent_string)`** — returns `"chrome|macintosh"`: browser family and
platform, lowercased, with the version discarded. Blank or unparseable input returns `nil`. Uses
the `useragent` gem, which is already present as a direct dependency of `actionpack`; it will be
declared explicitly in the `Gemfile` because this code depends on it directly rather than
transitively.

Discarding the version is the whole point. Exact user-agent matching produces a false "new device"
event on every Chrome auto-update — roughly monthly, for every user.

**`SessionContext`** — a value object holding both, with:

- `SessionContext.from_request(request)`
- `#matches?(session)` — true when both `ip_prefix` and `device_fingerprint` equal the session's
- `#apply_to(session)` — writes both onto a session

### Stated limitation

`chrome|macintosh` cannot distinguish two different Chrome-on-macOS machines. The IP prefix is what
separates those. The signals are weak individually and are not represented as strong; what they
catch together is the realistic theft case, a cookie replayed from another network in another
browser, which trips both.

`matches?` requires equality on both fields. Two `nil`s compare equal, so a session whose context
could not be derived matches a request whose context also could not be derived. A `nil` against a
present value does not match.

## Step-up Reauthentication

### What a step-up does

A successful step-up **rewrites the session's recorded context to the current one** and stamps
`reauthenticated_at`. There is therefore one rule to reason about rather than two: either the
recorded context matches the request or it does not. Accepting a new network is the same operation
as proving you are still there.

If the context changes again later — the phone moves again — the session returns to unverified.
That is correct: each new network is separately vouched for.

### Three gates

All three live in a `Reauthentication` controller concern. Two ask about the context and differ only
in whether they tolerate a recent step-up; the third ignores the context entirely.

**`require_matching_context`** — the strict form. Redirects to the challenge unless
`SessionContext.from_request(request).matches?(Current.session)`.

**`require_matching_context_or_recent_step_up`** — the tolerant form. Also passes when the session
was stepped up within `Session::REAUTH_FRESHNESS`. Added to `Admin::BaseController` after the
existing `require_admin` and `require_admin_passkey` callbacks.

Placed at the admin boundary rather than on a list of actions, so every admin screen is covered,
including screens built later. There is no allowlist that someone can forget to update.

**`require_fresh_reauthentication`** — requires `reauthenticated_at` within
`Session::REAUTH_FRESHNESS` (15 minutes), *regardless* of whether the context matches.

This gate exists because context matching structurally cannot catch a live session on a stolen
unlocked laptop: same network, same browser, same everything. Fifteen minutes matches `MagicLink`
expiry, so a link that took twelve minutes to arrive still grants a usable window.

Applied to:

| Action | Context gate | Freshness gate | Why |
|---|---|---|---|
| Every `Admin::BaseController` descendant | Tolerant | — | Whole boundary; no allowlist to forget |
| `Admin::UsersController#destroy` | **Strict** | Yes | Irreversible; deletes an account and everything attached |
| `Admin::MembershipApplicationsController#destroy` | **Strict** | Yes | Irreversible |
| `Admin::UsersController#create` | **Strict** | Yes | Creates an admin account |
| `Admin::UsersController#toggle_admin` | **Strict** | Yes | Grants admin; durable privilege escalation |
| `PasskeysController#registration_options`, `#registration` | **Strict** | Yes | Adds a credential to the account |
| `PasskeysController#destroy` | **Strict** | Yes | Removes a credential from the account |

`PasskeysController#authentication_options` and `#authentication` carry neither. They are the
unauthenticated sign-in path; there is no session to match a context against, and gating them would
break passkey sign-in outright.

### Why the two context gates differ

The asymmetry is the point, and each half exists because of the other.

**The admin boundary tolerates churn because it is checked on every page load.** On an egress whose
address rotates across /24 boundaries between requests — iCloud Private Relay, carrier CGNAT, a
corporate proxy pool — a strict check there challenges, accepts the step-up, and challenges again on
the very next page, unbounded. The step-up rewrites the context, but the context has already moved
again. Honouring a step-up for its 15-minute window is what turns that loop into one tap. A gate that
cannot be satisfied is a lockout, and lockout is the risk this design is shaped around.

**Passkey add and remove stay strict because they are already gated on freshness.** If the context
check there also passed on freshness, it would be redundant with `require_fresh_reauthentication` and
would catch nothing: a cookie stolen and replayed from another network within fifteen minutes of the
victim's sign-in — sign-in stamps `reauthenticated_at` — would register an attacker's credential with
nothing tripped. That is the account-takeover persistence move in a passwordless system, and it is
exactly the remote-replay case the context signal exists to catch. Changing a credential is one
deliberate action rather than a page loaded repeatedly, so an extra tap after a network change is an
acceptable price and no loop can form.

The named cost of the grace: within the 15 minutes after a genuine sign-in or step-up, a replayed
cookie from another network can read the admin area and reach the actions gated on freshness alone.
That window was accepted in exchange for an admin area that is usable from a rotating egress. The
credential surface, which is where a stolen session becomes permanent, is not part of the trade.

The passkey actions are self-service — `PasskeysController` is the member's own
`/settings/security`, and `load_current_user_credential` scopes to
`current_user.passkey_credentials`. No admin can manage another user's passkeys, and this design
does not add that ability.

They are gated because in a passwordless system, adding a passkey is the account-takeover
persistence move: an attacker holding a stolen session cookie adds their own credential and gains
durable independent access that outlives the cookie, with no password to change to evict them.
Removal is the mirror threat — strip an admin's only passkey and `require_admin_passkey` locks them
out of their own site.

## Known Contexts

A raw IP change is the weakest signal in this design and the one most prone to firing on nothing.
Comparing a request against *the last request* is not what mature identity providers do: Microsoft
Entra's "unfamiliar sign-in properties", Okta's adaptive policies and Auth0's Adaptive MFA all score
a request against a **learned baseline of that user's own history**, and treat a single changed
address as weak input rather than a verdict. Impossible travel is a signal; a different address is
not.

`KnownContext` is a small version of that idea, built with no external data and no GeoIP database.

### The model

| Column | Notes |
|---|---|
| `user_id` | FK, not null |
| `ip_prefix` | The `NetworkPrefix` value; nullable |
| `device_fingerprint` | The `DeviceFingerprint` value; nullable |
| `last_seen_at` | Not null; when this context was last used |

Unique on `(user_id, ip_prefix, device_fingerprint)` **with `nulls_not_distinct: true`**, indexed on
`last_seen_at` for the sweep.

The `nulls_not_distinct` is load-bearing, not decoration. Postgres treats two `NULL`s as distinct by
default, so a plain unique index would let `(user, nil, nil)` — or any pair with one nil half —
insert a fresh duplicate row on every single sign-in, silently defeating both the uniqueness the
upsert relies on and the `MAX_PER_USER` cap. Either half is legitimately nil whenever `NetworkPrefix`
or `DeviceFingerprint` cannot derive a value, which is not an edge case: a request with no
`User-Agent` header produces a nil fingerprint, and the test suite's own default does exactly that.

**A known context is the pair, not the prefix alone.** Remembering only networks would discard the
device half, which is the stronger of the two — a new browser on a familiar network is a real
signal and should still ask. Since `DeviceFingerprint` already drops the version, a browser update
does not create a new pair.

`KnownContext::MAX_PER_USER` is 10, evicted least-recently-seen. `KnownContext::RETENTION` is
90 days, swept by `ExpiredAuthRecordsCleanupJob`.

### How it composes with the gates

Deliberately **additive**. The context gates gain one more way to pass; nothing existing changes
meaning:

- **tolerant** — the session's anchor matches, **or** the context is known for this user, **or** the
  session was stepped up inside `REAUTH_FRESHNESS`
- **strict** — the session's anchor matches, **or** the context is known for this user

A context is remembered when a session is created and when a step-up succeeds — both are moments the
user has just proved who they are. It is *not* remembered merely by being matched, or an attacker's
network would enrol itself. Matching touches `last_seen_at` at most once a day, so an actively used
context does not age out while a genuinely abandoned one does.

A context whose prefix and fingerprint are both nil is never recorded. It carries no information and
would match every other undetermined request.

### What this costs and what it buys

**Buys:** a member who moves between home, work and phone stops being challenged after the first
visit from each. That is the churn that would otherwise make the feature feel broken, and it is
removed without weakening the device signal or coarsening the prefix.

**Costs, stated plainly:** a cookie replayed from a network the *user* has used before — the same
café wifi, the same office — passes the context check. Per-session anchoring would have caught that
and this does not. It is the same trade every provider in the paragraph above makes, because the
alternative is a challenge on every legitimate move, and a gate people learn to click through
protects nothing.

**Privacy:** this retains a coarse location trail per member on a civic site whose members did not
ask for it. A /24 is not an address, but it is not nothing. The 90-day sweep, the cap of 10, and
listing the records back to the member on `/settings/security` are all part of the deal — a member
can see exactly what is stored about them, which is the standard this project should hold itself to.

### Gate failure responses are format-aware

All three gates guard HTML actions and JSON endpoints, and a redirect is wrong for the latter.

- **HTML** — redirect to `/reauthentication/new`, storing the original URL in
  `session[:return_to_after_authenticating]`. This is the same slot the sign-in flow uses, and it is
  consumed by the existing `after_authentication_url`, so both step-up paths return the user to
  where they were headed with no new mechanism.
- **JSON** — `head :forbidden`. `PasskeysController#registration_options` and `#registration` are
  fetched by `passkey_controller.js`, which would treat a 302 to an HTML page as a malformed
  options response and report a misleading error.

Because a bare 403 gives the member nothing to act on, `/settings/security` also gates its passkey
management controls at the page level, asking the *same* pair of questions the controller asks —
freshly reauthenticated **and** an exactly matching context. When either is missing, the "Add a
passkey" button and the per-credential "Remove" links are replaced by a single link to the challenge
page. Gating the page on freshness alone would render a button whose endpoint answers 403, and
`passkey_controller.js` would report that as a failed ceremony rather than as a step-up prompt. The
JSON 403 is then unreachable through normal use and exists as defence in depth, because a UI-level
gate is not a security control.

`PasskeysController#destroy` is an ordinary HTML delete, so it takes the redirect path.

### Sign-in counts as reauthentication

`start_new_session_for` stamps `reauthenticated_at` alongside the context. A fresh sign-in *is* a
proof of identity, so a new member has 15 minutes to add their first passkey without a second email
round trip. Without this, first-passkey setup would require two magic links, and the second would
arrive with no way for the member to understand why.

## The Challenge Flow

`ReauthenticationsController`, at `/reauthentication`:

| Action | Method | Purpose |
|---|---|---|
| `new` | GET | The challenge page |
| `passkey_options` | POST, JSON | WebAuthn get options for `Current.user`'s credentials |
| `passkey` | POST, JSON | Verify, mark the session, return a redirect target |
| `magic_link` | POST | Email a sign-in link, redirect with a notice |

The controller includes **neither gate**. Including either produces an infinite redirect, and that
gets an explicit test rather than a comment.

### Passkey path

Verifies the assertion against `Current.user`'s credentials and marks the **existing** session. It
does not create a new session, which is what distinguishes step-up from sign-in.

`PasskeysController` currently holds the WebAuthn verification helpers as private methods. They move
to a `WebauthnVerification` controller concern shared by both controllers rather than being
duplicated — a targeted cleanup of code this feature is touching, not a general refactor.

**No new JavaScript.** `passkey_controller.js` reads its four endpoints from `data-*` attributes and
already follows `payload.redirect_to`, so the challenge page reuses the existing Stimulus controller
by pointing `authenticationOptionsUrl` and `authenticationUrl` at the reauth endpoints.

### Magic-link path is the ordinary sign-in link

Deliberately not a new magic-link purpose and not a new Loops template.

The reason is a failure mode that a dedicated reauth link would walk straight into: the emailed link
frequently opens in a **different browser** than the one awaiting reauthentication — tapped from a
phone's mail client while the admin session sits in desktop Chrome. In that browser there is no
session to mark, and a reauth-purpose token would have nothing to apply to.

Treating it as a sign-in makes any browser the link lands in end up with a fresh, context-anchored,
recently-reauthenticated session, redirected to the original destination through the existing
`session[:return_to_after_authenticating]` mechanism. It reuses `TransactionalEmail.magic_link` and
the existing `sign_in_magic_link` Loops template, so **no new production configuration is required**.

`ReauthenticationsController#magic_link` is rate limited per IP with the existing
`rate_limit to: 10, within: 3.minutes` pattern, and the passkey endpoints get their own limit. Each
declaration carries an explicit `name:`, because Rails keys the counter on
`["rate-limit", scope, name, by]` and defaults `scope` to the controller path: unnamed, the two would
share one budget. Sharing it would mean five failed passkey taps (two requests each) exhaust the
budget and the email fallback answers "Try again later." — the fallback consumed by the failures it
exists to rescue. This is the only controller in the app with two limits.

`magic_link` deliberately does **not** record a
`SignInAttempt`: the caller is already authenticated so there is no address to enumerate, and
recording one would let a member burn their own 15-minute sign-in throttle from inside the app.

### Challenge page

Follows the Living Room theme and the design system — colors via custom properties, Outfit for the
heading, Space Grotesk for body copy. No emoji.

The passkey button is **omitted entirely** when `Current.user` has no credential, rather than
rendered and failing. A member past their 15-minute window with no passkey would otherwise be
offered a button that cannot work. Those members see only the email option.

## Audit Trail

`AuditEvent`:

| Column | Notes |
|---|---|
| `actor_id` | FK to users, `dependent: :nullify` |
| `actor_email` | Snapshot; survives deletion of the actor |
| `action` | e.g. `"user.destroy"` |
| `subject_type` / `subject_id` | Polymorphic, nullable |
| `subject_label` | Snapshot; the subject of a deletion no longer exists to join to |
| `metadata` | jsonb |
| `ip_address` | From the request |

The two snapshot columns are the point. An audit trail that stores only foreign keys loses exactly
the rows it exists to record, because the destructive actions it covers delete their own subjects.

Written through `AuditEvent.record!(actor:, action:, subject:, label:, request:, metadata: {})` from
the destructive admin actions: user create and destroy, application destroy, approve, reject,
`toggle_admin`, `disable`, `revoke_session`, `revoke_all_sessions`, and access mode changes.

A read-only `/admin/audit_events` index ships with it. A trail nobody can read is close to
worthless.

### The association that must not be forgotten

`User` gains:

```ruby
has_many :audit_events, foreign_key: :actor_id, inverse_of: :actor, dependent: :nullify
```

Without it, `audit_events.actor_id` is a foreign key to `users` with no cascade, and deleting a user
who has ever recorded an audit event raises `ActiveRecord::InvalidForeignKey`. User deletion is one
of the actions this trail exists to record, so the trail would break the very operation it audits —
and it would break it only for accounts that had done admin work, meaning it would pass a naive test
against a freshly created user and fail in production against the owner.

`User` already documents this exact hazard for `reviewed_membership_applications`,
`uploaded_generated_images` and `topic_review_events`. This is a fourth instance of the same
pattern, and `actor_email` is why `:nullify` loses nothing.

## Cleanup

`ExpiredAuthRecordsCleanupJob`, daily at 4am via `config/recurring.yml`, deleting in batches:

- Sessions past `INACTIVITY_LIMIT` or `ABSOLUTE_LIFETIME`
- `MagicLink` rows that are used or expired
- `SignInAttempt` rows older than `SignInAttempt::WINDOW`
- `KnownContext` rows past `KnownContext::RETENTION`

All four accumulate forever today. `SignInAttempt` gains a row per sign-in attempt and is only ever
read inside a 15-minute window; `MagicLink` rows are dead the moment they are used; `KnownContext`
rows are a coarse location trail with no further use once stale, which is the deal the retention
section above describes.

Idempotent per repo convention: safe to re-run, deletes only rows already unusable.

## Implementation Phasing

Two phases, deployable independently. The split is not arbitrary: phase 1 is the part that can lock
the owner out, and it should reach production and be confirmed working before anything else is
layered on top of it.

**Phase 1 — session policy and step-up.** Lifetime constants, the three value objects, the context
migration and its backfill, the two gates, `ReauthenticationsController` and its page, the
`WebauthnVerification` extraction, and the `/settings/security` page-level gate.

**Phase 2 — audit trail and cleanup.** `AuditEvent` and its migration, the `User` association, the
recording calls, `/admin/audit_events`, and `ExpiredAuthRecordsCleanupJob` with its
`config/recurring.yml` entry. Nothing here can deny access to anyone.

## Out of Scope

**Email change.** `Settings::ProfileController` is show-only; there is no email-change feature in the
app. Building one inside a hardening project would be scope creep in the wrong direction.

**Cross-browser reauthentication by transferable code.** Deferred deliberately, and expected to be
built later.

This design resolves the wrong-browser problem by signing the user in wherever the link lands. That
is correct and never strands anyone, but it is not what the user wanted when the *other* browser is
mid-task: an admin halfway through a review on desktop, who taps the link on their phone, ends up
signed in on the phone rather than unblocked on the desktop.

The intended eventual shape is a short code. The browser awaiting reauthentication displays or
accepts a code; the emailed link, opened anywhere, issues or confirms it; entering it on the
original browser completes the step-up there. This is the standard device-pairing pattern and it is
a meaningful amount of new surface — a code model with its own expiry and single-use semantics, a
second entry form, and rate limiting on guessing — which is why it is not being folded into this
project.

Nothing in this design blocks it. `Session#reauthenticate!` is the seam it would attach to.

**New-device email notification.** Genuinely useful, but requires a new Loops transactional template
and its own environment variable, which is production configuration work beyond a deploy.

**Revisiting the `if: :email_address_changed?` scope on `User`'s format validation.** Deliberate and
documented; unrelated to session policy.

**ASN-based IP matching.** Would need a MaxMind database shipped and refreshed on the VPS.

## Lockout Defence

Lockout is the primary risk, so each mitigation is stated as a requirement rather than an intention.

1. **The migration backfills** `ip_prefix` and `device_fingerprint` from the existing `ip_address`
   and `user_agent` columns, and sets `reauthenticated_at` to `created_at`. Live sessions are not
   thrown into step-up by the deploy. Backfilling `reauthenticated_at` from `created_at` is honest —
   the user did authenticate then — and harmless, because an old timestamp is not fresh.
2. **Pre-deploy production check**: count the sessions the 60-day rule will invalidate, and confirm
   `andre@xyzmodem.com`'s session is not among them. The count has to be taken against the *old*
   image, where `Session::INACTIVITY_LIMIT` is still 180 days, so the command writes 60 days out
   literally rather than reading the constant.
3. **Database backup before the migration**, per the `deploying` skill.
4. **Post-deploy verification**: sign in, enter `/admin`, complete a step-up, confirm admin access,
   then add and remove a passkey. The last step is the one that proves the recorded context is
   actually right, because the grace at the admin boundary can mask a wrong anchor for 15 minutes.
5. **Console recovery documented** in the `deploying` skill. The useful recovery is to *re-anchor* a
   session — write the `ip_prefix` and `device_fingerprint` the next request will actually produce,
   derived through `NetworkPrefix.for` and `DeviceFingerprint.for`. Stamping `reauthenticated_at`
   alone buys 15 minutes of admin access through the tolerant gate but does not satisfy the strict
   one. Setting the context columns to `nil` fixes nothing at all: `matches?` is strict equality
   including `nil`, so a nil-context row matches no real request.
6. **The magic-link fallback means no rule can fully block a member who can read their email.** This
   is the structural guarantee behind all of the above.

### Accepted cost

Entering `/admin` from a genuinely new network costs one passkey tap, and that tap then covers the
next 15 minutes even if the address keeps moving. Adding or removing a passkey from a network the
session has drifted away from costs a tap of its own, because that surface does not accept the grace.
On mobile, moving between cell towers can cross a /24, so occasional taps during phone admin use are
expected behaviour rather than a defect. This is recorded here so it is not later mistaken for a bug.

## Tests

Per the project standard, **every test is mutation-verified**: remove the guard it protects, confirm
the test fails, restore. Inspection is not evidence.

### Unit

- `NetworkPrefix` — IPv4 to /24, IPv6 to /48, malformed input, blank input, two addresses inside one
  /24 producing an equal prefix, and two addresses either side of a /24 boundary producing different
  prefixes
- `DeviceFingerprint` — stable across a browser version change, different across a browser family
  change, different across a platform change, `nil` for blank
- `SessionContext#matches?` — both equal, IP differs, device differs, both `nil`
- `Session` — `inactive?`, `beyond_absolute_lifetime?`, `expired?` for each combination

### Integration

- An expired session is cleared by `resume_session` (both expiry causes)
- Admin entry with a mismatched context and no recent step-up redirects to the challenge; with a
  matching context it does not
- Each fresh-reauth action rejects a stale session and accepts a fresh one
- A passkey step-up marks the session, updates its context, and does **not** create a second session
- The magic-link fallback signs in and honours the return-to
- `start_new_session_for` stamps `reauthenticated_at`, so first-passkey setup works immediately
- Audit events are written with actor and subject snapshots intact after the subject is deleted
- The cleanup job removes expired rows and leaves live ones

### The asymmetry gets a test file of its own

One session state — context drifted, step-up still fresh — asserted against both surfaces in the
same file, because the pair is the behaviour and neither half means anything alone:

- That state **reaches** `/admin`. Remove the grace and this fails, and the admin area loops on a
  rotating egress.
- That state **cannot** request registration options, register a credential, or remove one. Remove
  the strict gate and these fail, and a replayed cookie gains durable access.
- A control alongside them: the same session with its context restored *can* request registration
  options, so a refusal caused by something unrelated cannot pass as the gate working.

The two rate limits get a test too, proving the buckets are independent in both directions:
exhausting the passkey limit leaves the email fallback usable, and exhausting the email limit leaves
the passkey path usable. The test environment's `:null_store` makes rate limiting inert and each
declaration captures its store when the class body runs, so the test substitutes a counting store at
the one remaining seam — `ActionController::RateLimiting#rate_limiting`, which receives the store per
request — and forwards the real declared `name:`, `scope:` and `by:` to the real implementation.

### Tests that exist because this feature fails silently

- **`ReauthenticationsController` is reachable with an unverified context.** A redirect loop here
  locks out every admin at once, and it is invisible in unit tests.
- **Stale-reauth rejection is asserted per action, not per controller.** A previous review on this
  codebase found a guard whose real protection lived in a different method than the one under test.
  Each gated action gets its own assertion.
- **The migration backfill leaves a pre-existing session context-verified.** This is the single
  assertion standing between the deploy and every live member being challenged at once.
