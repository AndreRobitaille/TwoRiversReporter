# Passwordless auth operations

## Required production env vars
- `WEBAUTHN_ORIGIN`
- `WEBAUTHN_RP_ID`
- `WEBAUTHN_RP_NAME`
- `LOOPS_API_KEY`
- `ADMIN_NOTIFICATION_EMAIL`
- Optional transactional IDs:
  - `LOOPS_MAGIC_LINK_TRANSACTIONAL_ID`
  - `LOOPS_APPLICATION_LINK_TRANSACTIONAL_ID`
  - `LOOPS_ADMIN_APPLICATION_NOTIFICATION_TRANSACTIONAL_ID`

## Safety notes
- Production mail delivery fails closed when required Loops IDs or admin notification email are missing.
- Raw magic-link tokens are only embedded in ephemeral email URLs; they are not persisted as raw values in the database or queued job args.
- Admin access to `/admin` remains gated by both active admin status and a passkey credential.
- No password, TOTP, recovery-code, or MFA sign-in route remains in the app.

## Audit search
Checked for auth bypass indicators with:

```bash
rg "fake|bypass|preview|debug|password|totp|recovery_code|LOOPS|WEBAUTHN" app config test docs
```

Findings:
- Password/TOTP references are limited to historical docs/tests and passwordless admin assertions.
- `app/services/transactional_email.rb` uses env-gated transactional IDs and only renders magic-link URLs at send time.
- `app/controllers/admin/base_controller.rb` requires `Current.user.admin?`, `active_for_authentication?`, and a passkey credential.
- `app/controllers/sessions_controller.rb` remains the single sign-in path for magic links.
