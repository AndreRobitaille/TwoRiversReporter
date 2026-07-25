# Passwordless auth operations

## Required production env vars
- `WEBAUTHN_ORIGIN`
- `WEBAUTHN_RP_ID`
- `WEBAUTHN_RP_NAME`
- `LOOPS_API_KEY`
- `ADMIN_NOTIFICATION_EMAIL`
- Loops transactional IDs: see the **Loops Transactional Templates** table in
  `.claude/skills/deploying/SKILL.md`, which is the single source of truth for
  which templates exist, which env var carries each id, and which still need to
  be created in Loops. Do not duplicate the list here — it drifted once already.

`TransactionalEmail.verify_transactional_ids!` runs from
`config/initializers/verify_transactional_email_ids.rb` and makes a production
container refuse to boot when any of those ids is unset, so a missing id fails
the deploy rather than reaching a user.

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
- Password/TOTP references are limited to historical docs/tests, passwordless admin assertions, and unreachable legacy password reset views with no active routes.
- `app/services/transactional_email.rb` uses env-gated transactional IDs and only renders magic-link URLs at send time.
- `app/controllers/admin/base_controller.rb` requires `Current.user.admin?`, `active_for_authentication?`, and a passkey credential.
- `app/controllers/sessions_controller.rb` remains the single sign-in path for magic links.
