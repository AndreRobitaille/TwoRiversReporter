# Passwordless Auth — Visual Design Remediation

**Date:** 2026-07-24
**Branch:** `feature/passwordless-auth`
**Status:** Design approved
**Related:** `docs/superpowers/specs/2026-07-23-passwordless-auth-and-applications-design.md` (functional spec), `docs/plans/2026-03-28-atomic-design-system-spec.md` (binding visual spec)

## Problem

The passwordless auth feature is functionally complete and passes review, but its views were written against Tailwind utility classes. This project has no Tailwind. `application.css` is a single hand-written file served by Propshaft with a small bespoke utility set:

`flex` · `gap-2` · `gap-4` · `mb-0` · `mb-4` · `mb-6` · `mt-4` · `items-center` · `justify-between` · `text-sm` · `text-xs` · `flex-wrap`

Every other utility class in the branch is a no-op. The feature diff added **zero lines of CSS**.

### Confirmed phantom classes

`space-y-2` · `space-y-3` · `space-y-4` · `grid` · `lg:grid-cols-2` · `md:flex-row` · `md:items-center` · `md:justify-between` · `gap-3` · `p-4` · `font-semibold` · `min-w-0` · `break-all` · `whitespace-pre-wrap` · `rounded-lg` · `border-dashed` · `border-[var(--color-border)]` · `bg-[var(--color-surface-raised)]` · `tracking-[0.08em]` · `text-[var(--color-text-secondary)]`

### Resulting defects

| Surface | Defect |
|---|---|
| `sessions/new` | No styling whatsoever. Bare `<h1>`, unstyled `<input>`, raw `<button>`, literal status string `Ready.` visible to residents. Flash messages render via `tag.div` with no class. |
| `sessions/magic_link` | No styling. Interstitial copy does not explain why the extra click exists. |
| `applications/new` | Generic card; no step indicator on a 2-step flow. |
| `applications/edit` | Six ungrouped fields; City/State stack instead of pairing; optional Facebook field is indistinguishable from required fields; errors render as one `to_sentence` blob. |
| `settings/profile` | "2-column grid" renders as stacked full-width cards. Ten `<dt>` labels render as plain body text instead of DM Mono metadata. |
| `settings/security` | Passkey list has no spacing. Empty state renders as an unstyled paragraph. Row layout uses `justify-between` full-width sprawl — explicitly named in the design spec's anti-patterns. |
| `layouts/application` | Passkey prompt banner renders unspaced; `badge--warning` misused as a text label. Four flat account links appended to content nav with no separation. |
| `admin/users/index` | Six columns of raw `Yes`/`No`/`user.status` strings where the system calls for status chips. |
| `admin/users/show` | Raw `<h2>`/`<ul>`/`<div>` dumps. Session history and application review as unstyled bullet lists with naked `button_to`s. Raw un-localized timestamps. |

Emails are rendered externally by Loops; there are no in-app templates in scope.

## Scope

**View and CSS only.** No changes to auth logic, routes, controllers, or models — the completed security review stays valid.

## Design

### A. Public auth front door

Pages: `sessions/new`, `sessions/magic_link`, `applications/new`, `applications/edit`.

These keep the standard Living Room layout — site nav remains visible, because removing wayfinding from a civic site's apply page is hostile to residents.

New `.auth-*` family in `application.css`:

| Class | Definition |
|---|---|
| `.auth-panel` | 26rem centered column, `--color-surface`, `--radius-lg`, `--shadow-md`, `--space-8` padding |
| `.auth-panel--wide` | 34rem variant for the application form |
| `.auth-mark` | `shared/_starburst` at 44px, centered above the title |
| `.auth-title` | Outfit 900, `--text-3xl`, uppercase, `letter-spacing: -0.02em`, teal |
| `.auth-dek` | Space Grotesk, `--text-base`, `--color-text-secondary`, centered |
| `.auth-step` | DM Mono, `--text-xs`, uppercase, `0.12em` tracking, terra cotta — `STEP 1 OF 2` |
| `.auth-alt` | `OR` rule separating the magic-link form from the passkey button |
| `.form-row` | Real 2-col grid for City/State; collapses below 30rem |

`shared/_diamond_divider` sits between header and form.

**Typography note.** The approved mockup showed the email label in DM Mono. The binding design spec assigns form labels to Space Grotesk 500 `--text-sm` and reserves DM Mono for metadata, timestamps, and status. This spec follows the binding document: labels are Space Grotesk; DM Mono is used only for the step indicator and status region.

### B. Passkey status region

The current implementation ships the literal string `Ready.` to residents and only fails on unsupported browsers at click time.

- `.auth-status` renders empty and visually collapsed at idle.
- State modifiers, toggled by the Stimulus controller: `--working` (amber, "Waiting for your device…"), `--error` (brick), `--success` (forest).
- `aria-live="polite"` and `role="status"` are preserved; the region remains in the accessibility tree while visually collapsed.
- The controller feature-detects `window.PublicKeyCredential` on connect. When absent it disables the passkey button and explains why in plain language, instead of throwing on click.

### C. Account page

Nav becomes: `Meetings · Topics · Committees · About | Account · Admin (admins only) · Sign out`.

Admin remains a section link rather than an account link. Sign out renders subdued.

- New `settings/_header` and `settings/_tabs` partials, rendered by both existing views.
- Tabs reuse the existing `.tab-bar` / `.tab` component, server-rendered as two links to the existing routes with `aria-current="page"` on the active tab. Controllers, routes, and tests are untouched.
- `.detail-list` / `.detail-term` / `.detail-value` — new reusable definition-list pattern. DM Mono uppercase `--text-xs` terms, body-font values. Replaces ten hand-rolled label blobs.
- `.settings-grid` — real 2-column grid at ≥900px.
- Passkey list rebuilt as compact action cards with info and actions adjacent, replacing the full-width `justify-between` sprawl.
- Empty state uses the existing `.empty-state` component.

### D. Passkey reminder banner

Rebuilt on the existing `.attention-card--warning` component: amber left border, info and actions adjacent, per the design spec's attention-card pattern. The misused `badge--warning` text label is removed.

### E. Admin surfaces (Silo)

**`admin/users/index`** — status and state columns collapse into `.badge--*` chips; passkey count in DM Mono.

**`admin/users/show`** — full rebuild:

- Page header with account status chip row.
- Account actions as a button toolbar.
- Membership applications as `.attention-card` compact cards, terra-cotta left border when `submitted`, approve/reject grouped in-card with the rejection reason inline.
- Session history as a real `.table-wrapper` table: DM Mono IP and timestamps, user agent truncated with a `title` attribute, status chip, `.btn--danger .btn--sm` revoke.
- All raw `submitted_at` / `created_at` / `reviewed_at` values run through `l(..., format: :long)`.
- Passkeys shown as a count with a chip rather than the string `Present`.

### F. Sweep

Every phantom utility class listed above is removed branch-wide and replaced with real CSS.

## Verification

1. `bin/rails test` — full suite, expected to stay at 0 failures / 0 errors.
2. `bin/rubocop` — expected 0 offenses.
3. `grep` sweep confirming no phantom utility class remains in the branch's views.
4. Dev server on `0.0.0.0`; walk the real flow — sign in → magic link → apply → complete application → account (both tabs) → admin users index and show — capturing desktop and mobile-width screenshots of each.

No completion claim is made without screenshot and command output evidence.

## Out of Scope

- Email templates (rendered externally by Loops).
- Auth logic, routes, controllers, models.
- The admin layout and other admin pages not touched by this branch.
