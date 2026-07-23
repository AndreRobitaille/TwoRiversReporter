# Passwordless Auth and Member Applications Design

## Goal

Replace the existing password and OTP-based admin authentication with one unified passwordless account system for Two Rivers Reporter. The site should support public member applications, pending admin review, member-only access outside the public What's New page, passkey-backed admin access, and user-owned account security settings.

## Current Context

The app currently has a `users` table with `email_address`, `password_digest`, an `admin` boolean, TOTP fields, and recovery codes. Admin authentication is scoped under `/admin` and uses password login plus MFA in non-development environments. Public site pages generally assume unauthenticated access, while admin pages inherit from `Admin::BaseController` for role and MFA enforcement.

This design intentionally replaces the old auth behavior in one coordinated change rather than running a long-term hybrid password/passwordless system.

## Auth Model and Access Rules

`User` remains the core account record. Passwords, TOTP secrets, and recovery codes are removed from active authentication behavior and later removed from the schema once the replacement is complete.

Users sign in with:

- Magic links by email, available for approved active users.
- Passkeys, optional for normal members.

Admin remains a role/flag on `User`, not a separate account type or login system. Admin users must have at least one passkey before they can access `/admin`. An admin with no passkey may sign in by magic link, but any `/admin` request redirects them to security settings with a required passkey setup prompt. Admin access remains blocked until at least one passkey is registered.

The root What's New page remains public. Public exceptions also include sign-in, magic-link, passkey authentication, application, and required static/legal endpoints. Everything else requires login.

After login, every user lands on What's New. Admins see an admin link in the signed-in navigation when they are eligible for admin access.

## Application and Approval Flow

Public application is a two-step verified flow:

1. A visitor enters only their email address.
2. The app creates or updates a pending disabled account/application record and sends a Loops transactional email with a verification/application link.
3. The link opens the full application form.
4. The applicant submits first name, last name, street/city/state, Facebook profile URL, and application notes.
5. The account stays pending/disabled after submission.
6. Admins receive batched transactional email notifications for completed applications, no more than once per hour.
7. Admins review applications under `/admin/users` or a dedicated pending applications view.
8. Approval activates the user and automatically sends an approval/sign-in email with a time-limited magic link.
9. If that approval/sign-in magic link expires, the expired-link page offers a `send me a fresh link` action for that account/email. The user should not have to restart from the normal sign-in page.
10. Rejection keeps or marks the account as rejected/disabled so the email cannot silently reapply without admin awareness.

Application data should live in a separate `membership_applications` table rather than directly on `users`. This keeps authentication state focused on accounts while preserving application details, status, and review history.

## Account and Security Pages

Signed-in users get settings pages under `/settings`:

- `/settings/profile` shows account and application profile information read-only, including name, address, Facebook URL, and application details where appropriate.
- `/settings/security` lets the current user add, rename, and remove passkeys.

Normal members are not required to have passkeys. If a member has no passkeys after magic-link login, the app may show a small upper-right prompt encouraging passkey setup. The prompt is suppressible for about one week per user, stored in the database so it works across devices.

Passkey management is user-owned. Admins can see whether another user has passkeys but cannot rename, remove, or create another user's passkeys.

## Admin Account Management

`/admin/users` becomes the account management area. Admins can:

- Review pending applications.
- Approve or reject applications.
- View user details and application data.
- Toggle the admin role.
- Disable or re-enable users.
- Revoke active sessions.
- See whether a user has passkeys.
- View login/session history, including IP address, user agent, sign-in time, last seen time, and session status.

Admin actions require an authenticated active user, the admin role, and at least one registered passkey.

## Core Data Model

Keep or add auth-related user fields for:

- Normalized email address.
- Account state: pending, approved/active, rejected, disabled.
- Email verification timestamp.
- WebAuthn user handle.
- Passkey prompt suppression timestamp.
- Admin role.

Add supporting tables:

- `sessions`: server-side sessions referenced by signed cookies, with IP address, user agent, last seen time, and lifecycle state.
- `magic_links`: short-lived, single-use tokens stored only as digests. Links cover sign-in, application verification, approval sign-in, and approved-link replacement flows as needed.
- `passkey_credentials`: WebAuthn credentials scoped to a user.
- `membership_applications`: submitted application data, status, review metadata, and history needed for admin approval/rejection.

## Magic Links and Sessions

Magic links never sign users in on `GET`. A `GET` request shows a confirmation, expired, invalid, or resend page. A `POST` request consumes the token or requests a replacement link.

Magic links must be:

- Short-lived.
- Single-use.
- Stored only as HMAC digests, never raw tokens.
- Consumed in a transaction with row locking.

Disabled, pending, and rejected users cannot sign in. Missing, expired, and used magic links fail gracefully. Normal magic-link request responses must not reveal whether an account exists. The expired approval-link page may offer a replacement for the specific known link context without turning the general sign-in form into an email enumeration endpoint.

Session resume clears missing, expired, disabled, pending, rejected, or inactive sessions. Signing in resets the Rails session, creates a server-side session row, and stores only the signed session identifier in the browser cookie.

## Passkeys

Passkeys use WebAuthn with user verification required for both registration and authentication. Registration requires an authenticated active user and stores credentials under `current_user.passkey_credentials`. Authentication rejects unknown credentials and inactive users.

Credential rename and removal must scope through the current user. Admins do not manage other users' passkeys.

## Transactional Email and Loops

Loops sends transactional emails for:

- Application email verification links.
- Magic-link sign-in emails.
- Approval/sign-in links.
- Fresh approval links requested from an expired approval-link page.
- Batched admin notifications for completed applications.

Use a small `TransactionalEmail`/`LoopsDelivery` service boundary during implementation and testing. In production, this boundary must be hard-wired to real Loops delivery through credentials and environment configuration. No admin or user-facing setting may change the delivery backend, recipients, template IDs, or verification behavior.

Test and fake delivery modes are allowed only in test/development and must be environment-gated. Magic-link authority remains in the app database; Loops only transports links and never decides who can sign in.

Before launch, explicitly audit and remove any temporary bypasses, fake delivery hooks, preview tokens, debug routes, or console-only shortcuts that could weaken authentication.

## Error Handling and Abuse Resistance

- Preserve email-enumeration resistance for general sign-in and application start responses.
- Expired links should explain what happened and offer the safest next action.
- Pending, rejected, disabled, and inactive accounts should receive clear but non-enumerating responses where possible.
- Rate-limit magic-link requests, magic-link consumption, passkey authentication endpoints, and application email starts.
- Admin notification batching should prevent repeated email floods while still surfacing new applications within about one hour.
- Production passwordless email delivery must not expose runtime bypasses or test delivery controls.

## Tests

Add or update tests for:

- Password/TOTP auth paths are no longer used.
- Root What's New remains public while non-exempt pages require login.
- Magic links can be consumed once and expire correctly.
- Expired approval links can request a fresh link from the expired-link page.
- Disabled, pending, and rejected users cannot sign in.
- Sign-in and application start responses do not reveal whether an email exists.
- Application email verification opens the full application form.
- Application submission creates or updates pending disabled account/application state.
- Admin notification batching sends no more than one notification batch per hour.
- Admin approval activates the user and sends an approval/sign-in link.
- Admin rejection prevents silent reapplication.
- Passkey registration and authentication enforce WebAuthn challenges and user verification.
- Admin users without passkeys cannot access `/admin` and are redirected to security setup.
- Members can manage only their own passkeys.
- Admins can view passkey presence but cannot manage another user's passkeys.
- Session resume clears missing, expired, disabled, pending, rejected, inactive, or revoked sessions.
- Admin account management can approve/reject, toggle admin role, disable/re-enable users, revoke sessions, and show login/session history.

At least one system test should cover the happy path: email verification, application submission, admin approval, approval magic-link sign-in, and first member access.

## Out of Scope

- Public self-registration without admin approval.
- Password login fallback.
- OTP/TOTP fallback.
- Admin management of another user's passkeys.
- Editable member profile fields beyond passkey/security settings.
- In-app notification center for applications.
- Mandatory passkeys for normal members.
