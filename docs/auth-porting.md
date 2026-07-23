# Porting the Passwordless Auth Setup

This document describes the login, passkey, session, and security/profile setup in LegionPostTools, then lays out a plan to recreate the same pattern in another Rails app.

The target app can be unrelated to American Legion use. Treat the code here as a Rails passwordless authentication reference, not as a product-specific dependency.

## What This App Implements

LegionPostTools uses passwordless authentication with two sign-in paths:

- Magic links by email as the universal recovery and first sign-in path.
- Passkeys using WebAuthn as a faster sign-in path after a user has registered one.

It does not use passwords. A user signs in by requesting an email link, confirming that link, and receiving a durable signed session cookie. Once signed in, the user can add, rename, and remove passkeys from a security settings page.

The core pieces are:

- `User`: owns the login email, disabled state, WebAuthn user handle, and passkey credentials.
- `Session`: server-side session record referenced by a signed cookie.
- `MagicLink`: short-lived, single-use login token stored only as a digest.
- `PasskeyCredential`: stored WebAuthn credential for one registered passkey.
- `Current.session`: request-local current session state.
- `SessionsController`: email link request, magic-link confirmation, sign-out.
- `PasskeysController`: JSON endpoints for WebAuthn registration and authentication, plus passkey rename/remove.
- `Settings::SecurityController`: profile/security page showing the user's passkeys.
- Stimulus `passkey_controller.js`: browser-side WebAuthn ceremony glue.
- Mail delivery seam and `MagicLinksMailer`: sends the sign-in email.

## Current Data Model

### `users`

Relevant auth columns:

- `email_address`: normalized to lowercase and used for magic-link lookup.
- `disabled_at`: when present, the account cannot sign in and existing sessions are invalidated on next request.
- `email_verified_at`: set when a magic link is successfully consumed.
- `webauthn_id`: opaque, unique WebAuthn user handle generated with `WebAuthn.generate_user_id`.

LegionPostTools also ties `User` to `Person`, permission grants, roster status, and Legion-specific access rules. Those are not required for a generic app.

For another Rails app, keep the auth-relevant columns and replace `belongs_to :person` with whatever profile or account model the app uses. If the new app has no separate profile model, `User` can directly own display name fields.

### `sessions`

Fields:

- `user_id`
- `ip_address`
- `user_agent`
- `last_seen_at`
- timestamps

The browser stores only `cookies.signed.permanent[:session_id]`. The server looks up that row on each request. Sessions expire after inactivity, currently `180.days`, and `last_seen_at` is touched at most every `15.minutes`.

### `magic_links`

Fields:

- `user_id`
- `token_digest`
- `expires_at`
- `used_at`
- timestamps

The raw token is generated with `SecureRandom.urlsafe_base64(32)` and is only available immediately after creation. The database stores an HMAC SHA256 digest using `Rails.application.secret_key_base`. Links expire after `15.minutes` and are single-use.

### `passkey_credentials`

Fields:

- `user_id`
- `external_id`: WebAuthn credential id, unique.
- `public_key`
- `sign_count`
- `nickname`
- `last_used_at`
- timestamps

Each row represents one registered authenticator. Users can register multiple passkeys and optionally name them.

## Request Flows

### Magic-Link Sign-In

1. User visits `GET /session/new`.
2. User submits email to `POST /session`.
3. `SessionsController#create` normalizes the email and looks up an enabled user.
4. If found, `MagicLink.create_for!(user)` creates a short-lived token and stores only its digest.
5. `MailDelivery.deliver_magic_link` sends `GET /session/magic_link?token=...`.
6. The app always redirects with `Check your email for a login link`, even if no account exists. This avoids email enumeration.
7. User opens the link and sees a confirmation form at `GET /session/magic_link`.
8. User submits `POST /session/magic_link` with the token.
9. `MagicLink.consume!` validates the digest, expiry, unused state, and user enabled state inside a transaction with row locking.
10. On success, `start_new_session_for(user)` resets the Rails session, creates a `Session` row, writes the signed cookie, and redirects to root.

Rate limits:

- Magic-link requests: 10 per 5 minutes by normalized email plus IP.
- Magic-link consumption: 30 per 5 minutes by IP.

### Passkey Registration

1. Authenticated user opens the security settings page or dashboard passkey prompt.
2. Stimulus posts to `POST /passkeys/registration_options`.
3. Rails calls `WebAuthn::Credential.options_for_create` with:
   - `user.id`: `current_user.webauthn_id`
   - `user.name`: `current_user.email_address`
   - `user.display_name`: `current_user.person.full_name` in this app
   - `resident_key: "required"`
   - `user_verification: "required"`
   - `exclude`: existing credential ids for this user
4. The challenge is stored in `session[:webauthn_registration_challenge]`.
5. Browser runs `create({ publicKey: options })` from `@github/webauthn-json`.
6. Stimulus posts the resulting credential to `POST /passkeys/registration` with optional `nickname`.
7. Rails verifies the challenge with `user_verification: true`.
8. Rails stores the credential under `current_user.passkey_credentials`.

### Passkey Authentication

1. User clicks `Sign in with a passkey` on the sign-in page.
2. Stimulus posts to `POST /passkeys/authentication_options`.
3. Rails calls `WebAuthn::Credential.options_for_get`, stores the challenge, and returns options.
4. Browser runs `get({ publicKey: options })` from `@github/webauthn-json`.
5. Stimulus posts the assertion to `POST /passkeys/authentication`.
6. Rails finds the stored credential by `external_id`.
7. Rails rejects missing credentials and disabled users.
8. Rails verifies the assertion against the stored public key and sign count with `user_verification: true`.
9. Rails updates `sign_count` and `last_used_at`.
10. Rails starts a new server-side session and returns JSON success.
11. Stimulus redirects to `/`.

Rate limits:

- Authentication options: 20 per 5 minutes by IP.
- Authentication submission: 20 per 5 minutes by IP.

### Session Resume And Sign-Out

Every request runs `resume_session` in `ApplicationController`:

1. Read `cookies.signed[:session_id]`.
2. Find the `Session` row.
3. Clear the cookie if the session is missing.
4. Destroy the session and clear the cookie if the user is disabled.
5. Destroy the session and clear the cookie if inactive longer than `SESSION_INACTIVITY_LIMIT`.
6. Touch `last_seen_at` if older than `SESSION_TOUCH_INTERVAL`.
7. Set `Current.session`.

Sign-out destroys the current `Session`, clears `Current.session`, deletes the cookie, and redirects to sign in.

## Profile And Security Surface

This app's profile/security setup is intentionally small:

- The signed-in user sees authenticated navigation.
- `Settings::SecurityController#show` requires authentication.
- The security page lists all passkeys for `current_user` ordered by creation date.
- Each passkey can be renamed with `PATCH /passkeys/:id`.
- Each passkey can be removed with `DELETE /passkeys/:id`.
- The page includes an "Add a new passkey" block driven by the same Stimulus controller.

There is also a dashboard prompt for users with no passkeys. They can dismiss it using `PasskeyInvitationsController`, which stores `session[:passkey_invite_dismissed] = true`.

In another app, this can become a profile page, account settings page, or security tab. The important behavior is that passkey management is scoped to `current_user.passkey_credentials`, not arbitrary credential ids.

## Files To Recreate Or Adapt

### Models

- `app/models/current.rb`
- `app/models/session.rb`
- `app/models/magic_link.rb`
- `app/models/passkey_credential.rb`
- Auth-relevant parts of `app/models/user.rb`

### Controllers

- Auth helpers from `app/controllers/application_controller.rb`
- `app/controllers/sessions_controller.rb`
- `app/controllers/passkeys_controller.rb`
- `app/controllers/settings/security_controller.rb`, or equivalent profile/security controller
- Optional: `app/controllers/passkey_invitations_controller.rb`

### JavaScript

- `app/javascript/controllers/passkey_controller.js`
- Importmap pin for `@github/webauthn-json`

### Mail

- `app/mailers/magic_links_mailer.rb`
- `app/views/magic_links_mailer/login.html.erb`
- `app/views/magic_links_mailer/login.text.erb`
- Optional mail provider seam in `app/services/mail_delivery.rb`

### Views

- `app/views/sessions/new.html.erb`
- `app/views/sessions/magic_link.html.erb`
- `app/views/settings/security/show.html.erb`, or equivalent profile/security page
- Authenticated layout/header changes that depend on `authenticated?` and `current_user`

### Configuration

- `gem "webauthn"`
- JavaScript package/importmap entry for `@github/webauthn-json`
- `config/initializers/webauthn.rb`
- Routes for sessions, passkeys, and security/profile page
- Mailer host configuration for generating absolute magic-link URLs

### Migrations

- Create `sessions`.
- Create `magic_links`.
- Create `passkey_credentials`.
- Add `webauthn_id` to `users` and backfill existing rows.
- Ensure the target app has `email_address`, `email_verified_at`, and `disabled_at` or equivalent user columns.

## App-Specific Pieces To Replace

Do not copy these parts directly into an unrelated Rails app without adapting them:

- `User belongs_to :person`: replace with the new app's profile model or direct user fields.
- `current_user.person.full_name`: replace with `current_user.name`, `current_user.email_address`, or another display name.
- `Organization.first` and entry-page branding: replace with the new app's branding.
- `redirect_to_setup_if_needed`, `Installation`, and setup recovery logic: only relevant to LegionPostTools first-run setup.
- `officer?`, `require_capability`, permission grants, roster access, and last-admin protections: use the new app's authorization model.
- Roster email review and login access override behavior: Legion-specific.
- Copy text that says LegionPostTools or American Legion only if the target app should say that.
- Dashboard passkey invitation card: optional product nudge, not required for auth correctness.

## Implementation Plan For A New Rails App

### 1. Prepare Dependencies

Add:

```ruby
gem "webauthn"
```

Install the browser helper:

```bash
bin/importmap pin @github/webauthn-json
```

Confirm the app already has Turbo/Stimulus/importmap or adapt the JavaScript ceremony to its asset stack.

### 2. Add User Auth Columns

For a typical `users` table, add:

- `email_address`, if not already present.
- `email_verified_at`.
- `disabled_at`.
- `webauthn_id`, unique and not null after backfill.

Normalize `email_address` in the model:

```ruby
normalizes :email_address, with: ->(value) { value.strip.downcase }
```

Generate `webauthn_id` on create:

```ruby
before_validation :assign_webauthn_id, on: :create

def assign_webauthn_id
  self.webauthn_id ||= WebAuthn.generate_user_id
end
```

### 3. Add Server-Side Sessions

Create the `sessions` table and model. Add helpers to `ApplicationController`:

- `current_user`
- `authenticated?`
- `require_authentication`
- `start_new_session_for(user)`
- `terminate_current_session`
- `resume_session`

Run `resume_session` before actions. Expose `current_user` and `authenticated?` as helper methods.

Use a signed, HTTP-only, same-site cookie containing only the server-side session id.

### 4. Add Magic Links

Create the `magic_links` table and model. Keep these properties:

- Raw tokens are never stored.
- Token digests use HMAC SHA256 with `Rails.application.secret_key_base`.
- Links expire quickly, currently 15 minutes.
- Links are single-use.
- Consumption happens in a transaction with row locking.
- The response to a login request is the same whether or not an account exists.

Create `SessionsController` with:

- `new`: renders email form.
- `create`: creates and emails a link if the user exists and is enabled.
- `magic_link`: GET renders confirmation; POST consumes token and signs in.
- `destroy`: signs out.

### 5. Add Mail Delivery

Create a mailer for the sign-in link. The simplest version can call Action Mailer directly:

```ruby
MagicLinksMailer.login(user, login_url).deliver_later
```

The `MailDelivery` seam in LegionPostTools is optional. Keep it if the target app may switch providers, such as between Action Mailer and an API-based email provider.

Make sure URL options are configured so `magic_link_session_url(token: token)` uses the correct host in development, test, and production.

### 6. Configure WebAuthn

Create `config/initializers/webauthn.rb`:

```ruby
WebAuthn.configure do |config|
  config.allowed_origins = [ENV.fetch("WEBAUTHN_ORIGIN")]
  config.rp_name = ENV.fetch("WEBAUTHN_RP_NAME")
  config.rp_id = ENV.fetch("WEBAUTHN_RP_ID")
end
```

For local development, use values matching the actual browser origin. If testing from another machine or HTTPS tunnel, do not leave the origin as `localhost` unless the browser is actually using localhost.

Example development values:

- `WEBAUTHN_ORIGIN=http://localhost:3000`
- `WEBAUTHN_RP_ID=localhost`
- `WEBAUTHN_RP_NAME=Your App Name`

Production must use HTTPS and a stable relying-party id, usually the registrable domain such as `example.com`.

### 7. Add Passkey Endpoints

Create `PasskeysController` with JSON endpoints:

- `POST /passkeys/registration_options`
- `POST /passkeys/registration`
- `POST /passkeys/authentication_options`
- `POST /passkeys/authentication`

Also add authenticated management endpoints:

- `PATCH /passkeys/:id`
- `DELETE /passkeys/:id`

Important rules:

- Registration requires an authenticated user.
- Authentication does not require an existing session.
- Challenge values are stored in the Rails session and deleted when used.
- Credential params must be explicitly permitted.
- Authentication must reject disabled users.
- Rename and remove must scope through `current_user.passkey_credentials`.

### 8. Add Browser WebAuthn JavaScript

Copy and adapt the Stimulus `passkey_controller.js`.

It should:

- Detect browser support with `supported()`.
- Disable passkey buttons if unsupported.
- Fetch registration/authentication options from Rails.
- Call `create` or `get` from `@github/webauthn-json`.
- POST the resulting credential/assertion back to Rails with the CSRF token.
- Show simple status/error messages.
- Redirect after success.

### 9. Add Views

Create:

- Sign-in page with email magic-link form and passkey button.
- Magic-link confirmation page that POSTs the token instead of signing in directly on GET.
- Security/profile page for passkey list, rename, remove, and add-new flow.

The GET confirmation step is intentional. It avoids treating link scanners, email previews, or accidental GET requests as sign-in attempts.

### 10. Add Routes

Equivalent route shape:

```ruby
resource :session, only: %i[new create destroy] do
  get :magic_link, on: :collection
  post :magic_link, on: :collection
end

resources :passkeys, only: %i[index update destroy] do
  collection do
    post :registration_options
    post :registration
    post :authentication_options
    post :authentication
  end
end

namespace :settings do
  resource :security, only: %i[show], controller: "security"
end
```

Adapt path names if the target app already has account/profile routes.

### 11. Add Rate Limits

Keep the rate limits or equivalents:

- Magic-link request by normalized email plus IP.
- Magic-link consumption by IP.
- Passkey authentication options by IP.
- Passkey authentication submission by IP.

The magic-link request action should still return the same message when a user does not exist.

### 12. Add Tests

At minimum, test:

- Magic links can be consumed once.
- Expired magic links fail.
- Magic links for disabled users fail.
- Token digest lookup does not require storing raw tokens.
- Login request does not reveal whether an email exists.
- Authenticated users can request passkey registration options.
- Unauthenticated users cannot register passkeys.
- Passkey registration stores credentials for the current user.
- Passkey authentication rejects unknown credentials.
- Passkey authentication rejects disabled users.
- Passkey rename/remove only affects the current user's credentials.
- Session resume clears missing, disabled, or inactive sessions.

Use controller/model tests for most of this. Add one system test for the magic-link flow. Real passkey ceremonies can be covered by lower-level controller tests unless the target app has browser automation support for virtual authenticators.

## Security Notes

- Never store raw magic-link tokens.
- Keep magic links single-use and short-lived.
- Do not sign users in on a GET request from an email link.
- Reset the Rails session before creating a new authenticated session.
- Use signed, HTTP-only cookies for the session id.
- Do not use the database id as the WebAuthn user handle.
- Require user verification for passkey registration and authentication.
- Scope passkey management through the current user.
- Reject disabled users in magic-link consumption, passkey authentication, and session resume.
- Configure WebAuthn origins and relying-party id carefully for each environment.
- Preserve email-enumeration resistance in the magic-link request response.

## Verification Checklist

After porting, run the target app's equivalent checks:

```bash
bin/rails test
bin/rubocop
bin/brakeman
bin/bundler-audit
```

Also manually verify:

- Requesting a magic link sends an email.
- Opening the link shows a confirmation page.
- Confirming the link signs in.
- Reusing the same link fails.
- Signing out clears access.
- Registering a passkey works in a supported browser over a valid secure context.
- Signing in with that passkey works after signing out.
- Removing the passkey prevents future passkey sign-in for that credential.

## Common Porting Pitfalls

- WebAuthn fails when `WEBAUTHN_ORIGIN` does not exactly match the browser origin.
- WebAuthn fails in production without HTTPS.
- Passkeys registered on one relying-party id cannot be used on another.
- Email link URLs fail if mailer host settings are missing.
- Copying `current_user.person.full_name` into an app without `Person` breaks passkey registration options.
- Copying setup or roster redirects can accidentally block login in a generic app.
- Authenticating directly on GET makes email-client link scanners consume login links.
- Returning "no account found" from login requests leaks registered emails.
