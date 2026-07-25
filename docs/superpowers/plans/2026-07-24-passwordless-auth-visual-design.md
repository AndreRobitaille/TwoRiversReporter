# Passwordless Auth Visual Design Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the passwordless auth branch's views up to the project's Atomic-era design system by replacing Tailwind classes that do not exist in this project with real, spec-compliant CSS.

**Architecture:** View and CSS only. Add a new `.auth-*` component family plus three small reusable patterns (`.detail-list`, `.settings-grid`, `.form-row`) to `app/assets/stylesheets/application.css`; rewrite nine views against real classes; reuse existing `.tab-bar`, `.attention-card`, `.empty-state`, `.table-wrapper`, `.badge--*` components. No auth logic, route, controller, or model changes — the completed security review must remain valid.

**Tech Stack:** Rails 8.1, Propshaft, hand-written `application.css` (no preprocessor, no Tailwind), Stimulus via ImportMap, Minitest.

## Global Constraints

- **No Tailwind.** This project has no Tailwind build. The only real utility classes are: `flex`, `gap-2`, `gap-4`, `mb-0`, `mb-4`, `mb-6`, `mt-4`, `items-center`, `justify-between`, `text-sm`, `text-xs`, `flex-wrap`. Anything else must be defined in `application.css` before use.
- **Type-scale tokens are `--font-size-*`, not `--text-*`.** `--text-sm` / `--text-xs` are **undefined** in this codebase. All new CSS must use `var(--font-size-sm)` etc.
- **No hardcoded hex values.** Use CSS custom properties only (`--color-teal`, `--color-terra-cotta`, `--color-brick`, `--color-forest`, `--color-amber`, `--color-text-secondary`, …).
- **Typography roles:** Outfit (`--font-display`) for headings, always uppercase. Space Grotesk (`--font-body`) for body text, buttons, **and form labels**. DM Mono (`--font-data`) for metadata, timestamps, status text, always uppercase with wide tracking.
- **Binding spec:** `docs/plans/2026-03-28-atomic-design-system-spec.md`. Where it conflicts with anything here, it wins.
- **Design spec for this work:** `docs/superpowers/specs/2026-07-24-passwordless-auth-visual-design.md`.
- **Themes:** public pages are `.theme-living-room` (starburst/boomerang allowed); admin is `.theme-silo` (atom marker, diamond divider, radar sweep only — **never** starburst or boomerang).
- **Working directory:** `/home/andre/Development/TwoRiversReporter/.worktrees/passwordless-auth` on branch `feature/passwordless-auth`.
- **Verification commands:** `bin/rails test`, `bin/rubocop`. Baseline before this work: 1280 runs, 0 failures, 0 errors, 1 skip; rubocop 0 offenses. These must still hold at the end.

## File Structure

**Modify:**
- `app/assets/stylesheets/application.css` — append one new section; fix one broken token reference in `.tab-bar .tab`.
- `app/views/sessions/new.html.erb` — rebuild.
- `app/views/sessions/magic_link.html.erb` — rebuild.
- `app/views/applications/new.html.erb` — rebuild.
- `app/views/applications/edit.html.erb` — rebuild.
- `app/views/settings/profile/show.html.erb` — rebuild.
- `app/views/settings/security/show.html.erb` — rebuild.
- `app/views/layouts/application.html.erb` — nav + passkey banner.
- `app/views/admin/users/index.html.erb` — badge chips.
- `app/views/admin/users/show.html.erb` — full rebuild.
- `app/javascript/controllers/passkey_controller.js` — status states + connect-time feature detection.
- `test/controllers/sessions_controller_test.rb:17` — update the `"Ready."` assertion.

**Create:**
- `app/views/settings/_header.html.erb` — shared Account page header.
- `app/views/settings/_tabs.html.erb` — shared Profile/Security tab bar.

---

### Task 1: CSS foundation

**Files:**
- Modify: `app/assets/stylesheets/application.css` (append new section at end; fix `.tab-bar .tab` at ~line 6009)

**Interfaces:**
- Produces: `.auth-panel`, `.auth-panel--wide`, `.auth-mark`, `.auth-title`, `.auth-dek`, `.auth-step`, `.auth-alt`, `.auth-status` (+ `--working`/`--error`/`--success`), `.auth-footnote`, `.form-row`, `.form-hint`, `.detail-list`, `.detail-term`, `.detail-value`, `.settings-grid`, `.passkey-list`, `.passkey-item`, `.passkey-item__name`, `.passkey-item__meta`. All later tasks consume these.

- [ ] **Step 1: Fix the broken token reference in `.tab-bar`**

`.tab-bar .tab` and its siblings reference `var(--text-sm)`, which is undefined. Replace with the canonical token. In `app/assets/stylesheets/application.css`, in the `.tab-bar .tab` rule only:

```css
  font-size: var(--font-size-sm);
```

Also replace the hardcoded fallback in `.tab-bar .tab.active`:

```css
.tab-bar .tab.active {
  color: var(--color-teal);
  border-bottom-color: var(--color-teal);
}
```

Do **not** mass-fix the other ~18 `var(--text-*)` usages elsewhere in the file — they belong to pages outside this branch's scope and changing them risks unverified visual regressions. Report them at the end instead.

- [ ] **Step 2: Append the new component section**

Add to the end of `app/assets/stylesheets/application.css`:

```css
/* ============================================
   Auth Front Door (Living Room)
   Sign in, magic link, membership application
   ============================================ */

.auth-panel {
  max-width: 26rem;
  margin: var(--space-12) auto;
  padding: var(--space-8);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-md);
}

.auth-panel--wide { max-width: 34rem; }

.auth-mark {
  display: flex;
  justify-content: center;
  margin-bottom: var(--space-4);
}

.auth-step {
  display: block;
  text-align: center;
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: var(--color-terra-cotta);
  margin-bottom: var(--space-2);
}

.auth-title {
  font-family: var(--font-display);
  font-weight: 900;
  font-size: var(--font-size-3xl);
  line-height: 1.1;
  text-transform: uppercase;
  letter-spacing: -0.02em;
  color: var(--color-teal);
  text-align: center;
  margin: 0;
}

.auth-dek {
  font-family: var(--font-body);
  font-size: var(--font-size-base);
  line-height: 1.5;
  color: var(--color-text-secondary);
  text-align: center;
  margin: var(--space-3) auto 0;
}

.auth-panel .diamond-divider {
  margin: var(--space-5) 0 var(--space-6);
  color: var(--color-terra-cotta);
}

.auth-panel .btn { width: 100%; justify-content: center; }

.auth-alt {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  margin: var(--space-6) 0 var(--space-4);
}

.auth-alt::before,
.auth-alt::after {
  content: "";
  flex: 1;
  height: 1px;
  background: var(--color-border);
}

.auth-alt span {
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: var(--color-text-muted);
}

/* Status region for passkey ceremonies.
   Collapsed but present in the a11y tree when idle. */
.auth-status {
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--color-text-secondary);
  margin: var(--space-3) 0 0;
  min-height: 0;
  display: flex;
  align-items: center;
  gap: var(--space-2);
}

.auth-status:empty { display: none; }

.auth-status::before {
  content: "";
  width: 6px;
  height: 6px;
  border-radius: var(--radius-full);
  background: currentColor;
  flex: none;
}

.auth-status--working { color: var(--color-amber); }
.auth-status--error   { color: var(--color-brick); }
.auth-status--success { color: var(--color-forest); }

.auth-footnote {
  font-family: var(--font-body);
  font-size: var(--font-size-sm);
  color: var(--color-text-secondary);
  text-align: center;
  margin: var(--space-6) 0 0;
}

/* Paired form fields (e.g. City / State) */
.form-row {
  display: grid;
  grid-template-columns: 2fr 1fr;
  gap: var(--space-3);
}

.form-row .form-group { margin-bottom: 0; }

@media (max-width: 30rem) {
  .form-row { grid-template-columns: 1fr; }
}

.form-hint {
  display: block;
  font-family: var(--font-body);
  font-size: var(--font-size-sm);
  color: var(--color-text-muted);
  margin-top: var(--space-1);
}

/* ============================================
   Detail List (reusable key/value pattern)
   ============================================ */

.detail-list { margin: 0; }

.detail-term {
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  font-weight: 400;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--color-text-secondary);
}

.detail-value {
  font-family: var(--font-body);
  font-size: var(--font-size-base);
  color: var(--color-text);
  margin: var(--space-1) 0 var(--space-4);
  overflow-wrap: anywhere;
}

.detail-value:last-child { margin-bottom: 0; }
.detail-value--preserve { white-space: pre-wrap; }

/* ============================================
   Account Settings
   ============================================ */

.settings-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: var(--space-6);
}

@media (min-width: 900px) {
  .settings-grid { grid-template-columns: 1fr 1fr; align-items: start; }
}

.passkey-list {
  list-style: none;
  padding: 0;
  margin: var(--space-4) 0 0;
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

.passkey-item {
  display: flex;
  align-items: center;
  gap: var(--space-4);
  padding: var(--space-3) var(--space-4);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-left: 4px solid var(--color-teal);
  border-radius: var(--radius-md);
}

.passkey-item__body { flex: 1; min-width: 0; }

.passkey-item__name {
  font-family: var(--font-display);
  font-weight: 600;
  font-size: var(--font-size-base);
  color: var(--color-teal);
  margin: 0;
  overflow-wrap: anywhere;
}

.passkey-item__meta {
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-secondary);
  margin: var(--space-1) 0 0;
}

/* ============================================
   Admin: account management (Silo)
   ============================================ */

.review-card { margin-bottom: var(--space-4); }
.review-card--pending { border-left-color: var(--color-terra-cotta); }

.review-card__actions {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  gap: var(--space-3);
  margin-top: var(--space-4);
  padding-top: var(--space-4);
  border-top: 1px solid var(--color-border);
}

.review-card__reason { flex: 1; min-width: 14rem; margin-bottom: 0; }

.data-cell {
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  color: var(--color-text-secondary);
  white-space: nowrap;
}

.truncate-cell {
  max-width: 20rem;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
```

- [ ] **Step 3: Verify the stylesheet still parses and nothing regressed**

Run: `bin/rails test test/controllers/settings/security_controller_test.rb`
Expected: PASS (CSS-only change; this confirms asset pipeline is not broken).

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "style: add auth front door and account settings components

Adds the .auth-*, .detail-list, .settings-grid, .form-row and
.passkey-item families the passwordless auth views need, plus admin
review/table helpers. Fixes .tab-bar's reference to the undefined
--text-sm token."
```

---

### Task 2: Sign-in and magic-link pages

**Files:**
- Modify: `app/views/sessions/new.html.erb`
- Modify: `app/views/sessions/magic_link.html.erb`
- Modify: `test/controllers/sessions_controller_test.rb:17`

**Interfaces:**
- Consumes: `.auth-panel`, `.auth-mark`, `.auth-title`, `.auth-dek`, `.auth-alt`, `.auth-status`, `.auth-footnote` from Task 1.
- Produces: the `data-passkey-target="status"` element now renders **empty**, with classes `auth-status`. Task 4's Stimulus controller writes into it.

- [ ] **Step 1: Update the test that asserts the literal string "Ready."**

The current assertion at `test/controllers/sessions_controller_test.rb:17` is:

```ruby
    assert_select "[data-passkey-target='status'][aria-live='polite'][role='status']", text: "Ready."
```

"Ready." is developer-facing noise shown to residents. Replace the assertion with one that pins the accessibility contract and the empty idle state:

```ruby
    assert_select "[data-passkey-target='status'][aria-live='polite'][role='status']", text: ""
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/sessions_controller_test.rb`
Expected: FAIL — the view still renders "Ready.", so the expected empty text does not match.

- [ ] **Step 3: Rebuild `app/views/sessions/new.html.erb`**

```erb
<% content_for(:title) { "Sign in" } %>

<div class="auth-panel">
  <div class="auth-mark"><%= render "shared/starburst", size: 44 %></div>

  <h1 class="auth-title">Sign in</h1>
  <p class="auth-dek">We'll email you a link that signs you in. No password to remember.</p>

  <%= render "shared/diamond_divider" %>

  <%= tag.div(flash[:alert], class: "flash flash--danger") if flash[:alert] %>
  <%= tag.div(flash[:notice], class: "flash flash--success") if flash[:notice] %>

  <%= form_with url: public_session_path, method: :post do |form| %>
    <div class="form-group">
      <%= form.label :email_address, "Email address", class: "form-label" %>
      <%= form.email_field :email_address,
            required: true, autofocus: true, autocomplete: "email",
            placeholder: "you@example.com", class: "form-input",
            value: params[:email_address] %>
    </div>

    <%= form.submit "Send magic link", class: "btn btn--primary" %>
  <% end %>

  <div data-controller="passkey">
    <div class="auth-alt"><span>or</span></div>

    <button type="button" class="btn btn--secondary" data-action="passkey#authenticate" data-passkey-target="trigger">
      Sign in with a passkey
    </button>

    <p class="auth-status" data-passkey-target="status" aria-live="polite" role="status"></p>
  </div>

  <p class="auth-footnote">
    New here? <%= link_to "Apply for an account", new_application_path %>.
  </p>
</div>
```

- [ ] **Step 4: Rebuild `app/views/sessions/magic_link.html.erb`**

This is the click-through interstitial that stops email scanners from consuming the token. The copy must explain that.

```erb
<% content_for(:title) { "Confirm sign in" } %>

<div class="auth-panel">
  <div class="auth-mark"><%= render "shared/starburst", size: 44 %></div>

  <h1 class="auth-title">One more tap</h1>
  <p class="auth-dek">
    Your link is valid. We ask for this extra tap so that automated email
    scanners can't use the link before you do.
  </p>

  <%= render "shared/diamond_divider" %>

  <%= form_with url: magic_link_public_session_path, method: :post do |form| %>
    <%= hidden_field_tag :token, @token %>
    <%= form.submit "Continue to my account", class: "btn btn--primary" %>
  <% end %>
</div>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/sessions_controller_test.rb test/integration/passwordless_application_flow_test.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/views/sessions test/controllers/sessions_controller_test.rb
git commit -m "style: rebuild sign-in and magic link pages

Both pages previously shipped with no styling at all. Adds the auth
panel treatment and replaces the developer-facing 'Ready.' status
string with an empty, aria-live status region."
```

---

### Task 3: Membership application flow

**Files:**
- Modify: `app/views/applications/new.html.erb`
- Modify: `app/views/applications/edit.html.erb`

**Interfaces:**
- Consumes: `.auth-panel`, `.auth-panel--wide`, `.auth-step`, `.form-row`, `.form-hint` from Task 1.

- [ ] **Step 1: Rebuild `app/views/applications/new.html.erb` as step 1 of 2**

```erb
<% content_for(:title) { "Apply for an account" } %>

<div class="auth-panel">
  <div class="auth-mark"><%= render "shared/starburst", size: 44 %></div>

  <span class="auth-step">Step 1 of 2</span>
  <h1 class="auth-title">Apply</h1>
  <p class="auth-dek">Tell us your email and we'll send a private link to finish the form.</p>

  <%= render "shared/diamond_divider" %>

  <%= tag.div(flash[:alert], class: "flash flash--danger") if flash[:alert] %>
  <%= tag.div(flash[:notice], class: "flash flash--success") if flash[:notice] %>

  <%= form_with url: applications_path, local: true do |form| %>
    <div class="form-group">
      <%= form.label :email_address, "Email address", class: "form-label" %>
      <%= form.email_field :email_address,
            required: true, autofocus: true, autocomplete: "email",
            placeholder: "you@example.com", class: "form-input",
            value: params[:email_address] %>
    </div>

    <%= form.submit "Send application link", class: "btn btn--primary" %>
  <% end %>

  <p class="auth-footnote">
    Already have an account? <%= link_to "Sign in", new_public_session_path %>.
  </p>
</div>
```

- [ ] **Step 2: Rebuild `app/views/applications/edit.html.erb` as step 2 of 2**

Group the six fields into three labelled fieldsets, pair City/State on one row, and mark the two optional fields as optional — currently they are visually indistinguishable from required ones.

```erb
<% content_for(:title) { "Complete your application" } %>

<div class="auth-panel auth-panel--wide">
  <span class="auth-step">Step 2 of 2</span>
  <h1 class="auth-title">Complete your application</h1>
  <p class="auth-dek">A few details so we know who you are. This goes to a person, not a robot.</p>

  <%= render "shared/diamond_divider" %>

  <% if @membership_application.errors.any? %>
    <div class="flash flash--danger">
      <ul class="mb-0">
        <% @membership_application.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <%= form_with model: @membership_application, url: application_path(@membership_application), method: :patch, local: true do |form| %>
    <%= hidden_field_tag :token, @token %>

    <div class="form-row">
      <div class="form-group">
        <%= form.label :first_name, "First name", class: "form-label" %>
        <%= form.text_field :first_name, required: true, autocomplete: "given-name", class: "form-input" %>
      </div>

      <div class="form-group">
        <%= form.label :last_name, "Last name", class: "form-label" %>
        <%= form.text_field :last_name, required: true, autocomplete: "family-name", class: "form-input" %>
      </div>
    </div>

    <div class="form-group">
      <%= form.label :street, "Street address", class: "form-label" %>
      <%= form.text_field :street, autocomplete: "street-address", class: "form-input" %>
      <span class="form-hint">Optional.</span>
    </div>

    <div class="form-row">
      <div class="form-group">
        <%= form.label :city, "City", class: "form-label" %>
        <%= form.text_field :city, required: true, autocomplete: "address-level2", class: "form-input" %>
      </div>

      <div class="form-group">
        <%= form.label :state, "State", class: "form-label" %>
        <%= form.text_field :state, required: true, maxlength: 2, autocomplete: "address-level1", class: "form-input" %>
      </div>
    </div>

    <div class="form-group">
      <%= form.label :facebook_profile_url, "Facebook profile", class: "form-label" %>
      <%= form.url_field :facebook_profile_url, placeholder: "https://www.facebook.com/your.name", autocomplete: "url", class: "form-input" %>
      <span class="form-hint">Optional. Helps us confirm you're a real neighbor.</span>
    </div>

    <div class="form-group">
      <%= form.label :application_notes, "Anything you'd like us to know", class: "form-label" %>
      <%= form.text_area :application_notes, rows: 5, class: "form-input" %>
      <span class="form-hint">Optional.</span>
    </div>

    <%= form.submit "Submit application", class: "btn btn--primary" %>
  <% end %>
</div>
```

- [ ] **Step 3: Run the tests**

Run: `bin/rails test test/controllers/applications_controller_test.rb test/integration/passwordless_application_flow_test.rb`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add app/views/applications
git commit -m "style: rebuild membership application flow

Adds step indicators, groups fields into paired rows, and marks the
three optional fields as optional. Validation errors render as a list
rather than one run-on sentence."
```

---

### Task 4: Passkey status states and connect-time feature detection

**Files:**
- Modify: `app/javascript/controllers/passkey_controller.js`

**Interfaces:**
- Consumes: `.auth-status--working` / `--error` / `--success` from Task 1; `data-passkey-target="trigger"` from Tasks 2 and 5.
- Produces: `#setStatus(message, state)` where `state` is one of `"working"`, `"error"`, `"success"`, or omitted to clear.

- [ ] **Step 1: Add the `trigger` target and a `connect` feature check**

Replace the `static targets` line and add a `connect` method immediately after it:

```js
  static targets = ["status", "trigger"]

  connect() {
    if (this.#supportsWebAuthn()) return

    this.triggerTargets.forEach((button) => {
      button.disabled = true
    })

    this.#setStatus("This browser doesn't support passkeys — use the email link instead.", "error")
  }
```

- [ ] **Step 2: Make `#setStatus` state-aware**

Replace the existing `#setStatus` method:

```js
  #setStatus(message, state) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message || ""
    this.statusTarget.classList.remove(
      "auth-status--working",
      "auth-status--error",
      "auth-status--success"
    )

    if (state) this.statusTarget.classList.add(`auth-status--${state}`)
  }
```

- [ ] **Step 3: Pass states at each existing call site**

Update every `#setStatus` call already in the file:

```js
// in #runCeremony
      this.#setStatus("Your browser doesn't support passkeys.", "error")
// in #runCeremony catch block
      this.#setStatus(error?.message || "That didn't work. Please try again.", "error")
// in #registerPasskey
    this.#setStatus("Preparing a new passkey…", "working")
    this.#setStatus("Waiting for your device…", "working")
    this.#setStatus("Passkey saved. Reloading…", "success")
// in #authenticateWithPasskey
    this.#setStatus("Checking for a passkey…", "working")
    this.#setStatus("Waiting for your passkey…", "working")
    this.#setStatus("Signed in. Redirecting…", "success")
```

- [ ] **Step 4: Verify the JS parses**

Run: `node --check app/javascript/controllers/passkey_controller.js`
Expected: no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/passkey_controller.js
git commit -m "fix: give passkey status region visible states

Colour-codes ceremony progress and disables the passkey button at
connect time on browsers without WebAuthn, instead of failing only
once the user clicks it."
```

---

### Task 5: Account page — nav, tabs, profile, security

**Files:**
- Create: `app/views/settings/_header.html.erb`
- Create: `app/views/settings/_tabs.html.erb`
- Modify: `app/views/settings/profile/show.html.erb`
- Modify: `app/views/settings/security/show.html.erb`
- Modify: `app/views/layouts/application.html.erb` (nav only; banner is Task 6)

**Interfaces:**
- Consumes: `.detail-list`, `.detail-term`, `.detail-value`, `.settings-grid`, `.passkey-list`, `.passkey-item*` from Task 1; existing `.tab-bar`/`.tab`, `.empty-state`, `.badge--*`.
- Note: `test/controllers/settings/security_controller_test.rb` asserts the body contains `"Register a passkey"` and `"Unnamed passkey"`, and that `"Unnamed passkey"` appears **before** `"Desk key"`. Preserve both strings and the list order.

- [ ] **Step 1: Create `app/views/settings/_header.html.erb`**

```erb
<div class="page-header">
  <h1 class="page-title">Account</h1>
  <p class="page-subtitle">Your details and how you sign in.</p>
</div>
```

- [ ] **Step 2: Create `app/views/settings/_tabs.html.erb`**

```erb
<nav class="tab-bar" aria-label="Account sections">
  <%= link_to "Profile", settings_profile_path,
        class: "tab #{'active' if current == :profile}",
        aria: { current: ("page" if current == :profile) } %>
  <%= link_to "Security", settings_security_path,
        class: "tab #{'active' if current == :security}",
        aria: { current: ("page" if current == :security) } %>
</nav>
```

- [ ] **Step 3: Rebuild `app/views/settings/profile/show.html.erb`**

```erb
<% content_for(:title) { "Account — Profile" } %>
<% content_for(:description) { "Read-only account and membership application details." } %>

<%= render "settings/header" %>
<%= render "settings/tabs", current: :profile %>

<div class="settings-grid">
  <section class="card">
    <div class="card-header">
      <h2 class="card-title">Account</h2>
    </div>

    <dl class="detail-list">
      <dt class="detail-term">Email address</dt>
      <dd class="detail-value"><%= current_user.email_address %></dd>

      <dt class="detail-term">Account status</dt>
      <dd class="detail-value">
        <span class="badge badge--<%= current_user.active_for_authentication? ? "success" : "warning" %>">
          <%= current_user.status.humanize %>
        </span>
      </dd>

      <dt class="detail-term">Admin access</dt>
      <dd class="detail-value"><%= current_user.admin? ? "Yes" : "No" %></dd>

      <dt class="detail-term">Passkeys</dt>
      <dd class="detail-value">
        <% count = current_user.passkey_credentials.count %>
        <%= count.positive? ? pluralize(count, "passkey") : "None yet" %>
      </dd>
    </dl>
  </section>

  <section class="card">
    <div class="card-header">
      <h2 class="card-title">Membership application</h2>
    </div>

    <% if @membership_application.present? %>
      <% application = @membership_application %>
      <% status_badge = case application.status
         when "approved" then "badge--success"
         when "rejected" then "badge--danger"
         when "submitted" then "badge--info"
         else "badge--default"
         end %>

      <dl class="detail-list">
        <dt class="detail-term">Status</dt>
        <dd class="detail-value">
          <span class="badge <%= status_badge %>"><%= application.status.humanize %></span>
        </dd>

        <% if application.first_name.present? || application.last_name.present? %>
          <dt class="detail-term">Name</dt>
          <dd class="detail-value"><%= [application.first_name, application.last_name].compact_blank.join(" ") %></dd>
        <% end %>

        <% if application.street.present? || application.city.present? || application.state.present? %>
          <dt class="detail-term">Address</dt>
          <dd class="detail-value">
            <%= safe_join([
                  application.street,
                  [application.city, application.state].compact_blank.join(", ")
                ].compact_blank, tag.br) %>
          </dd>
        <% end %>

        <% if application.facebook_profile_url.present? %>
          <dt class="detail-term">Facebook profile</dt>
          <dd class="detail-value">
            <%= link_to application.facebook_profile_url, application.facebook_profile_url,
                  target: "_blank", rel: "noopener" %>
          </dd>
        <% end %>

        <% if application.application_notes.present? %>
          <dt class="detail-term">Notes</dt>
          <dd class="detail-value detail-value--preserve"><%= application.application_notes %></dd>
        <% end %>

        <dt class="detail-term">Submitted</dt>
        <dd class="detail-value"><%= l(application.submitted_at || application.created_at, format: :long) %></dd>

        <% if application.reviewed_at.present? %>
          <dt class="detail-term">Reviewed</dt>
          <dd class="detail-value"><%= l(application.reviewed_at, format: :long) %></dd>
        <% end %>
      </dl>
    <% else %>
      <p class="card-body">You haven't started a membership application yet.</p>
      <%= link_to "Start an application", new_application_path, class: "btn btn--primary" %>
    <% end %>
  </section>
</div>
```

- [ ] **Step 4: Rebuild `app/views/settings/security/show.html.erb`**

```erb
<% content_for(:title) { "Account — Security" } %>
<% content_for(:description) { "Manage the passkeys attached to your account." } %>

<%= render "settings/header" %>
<%= render "settings/tabs", current: :security %>

<div class="card">
  <div class="card-header">
    <h2 class="card-title">Passkeys</h2>
    <p class="card-subtitle">
      Passkeys let you sign in without a password. They stay on your devices and
      use whatever unlocks them — a fingerprint, a face, or a PIN.
    </p>
  </div>

  <section
    data-controller="passkey"
    data-passkey-registration-options-url-value="<%= registration_options_passkeys_path(format: :json) %>"
    data-passkey-registration-url-value="<%= registration_passkeys_path(format: :json) %>"
    data-passkey-authentication-options-url-value="<%= authentication_options_passkeys_path(format: :json) %>"
    data-passkey-authentication-url-value="<%= authentication_passkeys_path(format: :json) %>"
  >
    <button type="button" class="btn btn--primary" data-action="passkey#register" data-passkey-target="trigger">
      Register a passkey
    </button>

    <p class="auth-status" data-passkey-target="status" aria-live="polite" role="status"></p>

    <% if @passkey_credentials.any? %>
      <ul class="passkey-list">
        <% @passkey_credentials.each do |credential| %>
          <li class="passkey-item">
            <div class="passkey-item__body">
              <p class="passkey-item__name"><%= credential.nickname.presence || "Unnamed passkey" %></p>
              <p class="passkey-item__meta">Added <%= l(credential.created_at.to_date, format: :long) %></p>
            </div>

            <%= link_to "Remove", passkey_path(credential),
                  class: "btn btn--danger btn--sm",
                  data: { turbo_method: :delete, turbo_confirm: "Remove this passkey?" } %>
          </li>
        <% end %>
      </ul>
    <% else %>
      <div class="empty-state mt-4">
        You haven't added any passkeys yet. Register one to make future sign-ins faster.
      </div>
    <% end %>
  </section>
</div>
```

- [ ] **Step 5: Update the nav in `app/views/layouts/application.html.erb`**

Replace the authenticated/unauthenticated nav block added by the branch with:

```erb
            <% if authenticated? %>
              <%= link_to "Account", settings_profile_path,
                    class: ("active" if current_path.start_with?("settings/")) %>
              <%= link_to "Admin", admin_root_path,
                    class: ("active" if current_path.start_with?("admin/")) if current_user&.admin_access_ready? %>
              <%= link_to "Sign out", public_session_path, data: { turbo_method: :delete } %>
            <% else %>
              <%= link_to "Sign in", new_public_session_path, class: ("active" if current_path == "sessions") %>
              <%= link_to "Apply", new_application_path, class: ("active" if current_path == "applications") %>
            <% end %>
```

- [ ] **Step 6: Run the tests**

Run: `bin/rails test test/controllers/settings test/integration/application_layout_auth_state_test.rb`
Expected: PASS. If `application_layout_auth_state_test.rb` asserts on the removed "Profile"/"Security" nav links, update those assertions to expect the single "Account" link — the nav consolidation is the intended change.

- [ ] **Step 7: Commit**

```bash
git add app/views/settings app/views/layouts/application.html.erb test
git commit -m "style: fold profile and security into one Account page

Adds a shared header and server-rendered tab bar over the two existing
routes, replaces ten hand-rolled label blobs with a reusable
.detail-list, and collapses four flat nav links into one Account entry."
```

---

### Task 6: Passkey reminder banner

**Files:**
- Modify: `app/views/layouts/application.html.erb`

**Interfaces:**
- Consumes: existing `.attention-card` / `.attention-card--warning` / `.attention-card__title` / `.attention-card__meta`.

- [ ] **Step 1: Replace the banner block**

The current markup misuses `badge--warning` as a text label and relies on `md:flex-row` / `justify-between`, none of which exist. Replace with the design system's attention-card pattern:

```erb
          <% if current_user.present? && !current_user.passkey_prompt_dismissed? && !current_user.passkey_credentials.exists? %>
            <div class="attention-card attention-card--warning mb-6">
              <p class="attention-card__title">Make your next sign-in faster</p>
              <p class="attention-card__meta">Add a passkey to this account</p>

              <div class="flex flex-wrap gap-2 mt-4">
                <%= link_to "Add a passkey", settings_security_path, class: "btn btn--secondary btn--sm" %>
                <%= link_to "Not now", settings_passkey_prompt_path,
                      class: "btn btn--ghost btn--sm",
                      data: { turbo_method: :delete } %>
              </div>
            </div>
          <% end %>
```

- [ ] **Step 2: Run the tests**

Run: `bin/rails test test/integration/application_layout_auth_state_test.rb`
Expected: PASS. If an assertion pins the old "Dismiss for a week" copy, update it to "Not now".

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/application.html.erb test
git commit -m "style: rebuild passkey reminder on the attention-card pattern

Replaces a badge misused as a text label and a sprawling
justify-between row with the design system's amber attention card."
```

---

### Task 7: Admin account management (Silo)

**Files:**
- Modify: `app/views/admin/users/index.html.erb`
- Modify: `app/views/admin/users/show.html.erb`

**Interfaces:**
- Consumes: `.review-card*`, `.data-cell`, `.truncate-cell` from Task 1; existing `.table-wrapper`, `.attention-card`, `.badge--*`, `.page-header`.
- Silo theme: **no starburst, no boomerang.**

- [ ] **Step 1: Replace the raw cells in `app/views/admin/users/index.html.erb`**

Collapse the Admin and Disabled columns into one State cell of chips, and chip the status:

```erb
      <tr>
        <th>Email</th>
        <th>Status</th>
        <th>State</th>
        <th>Passkeys</th>
        <th>Application</th>
      </tr>
```

```erb
        <tr>
          <td><%= link_to user.email_address, user_path(user) %></td>
          <td>
            <span class="badge badge--<%= user.active_for_authentication? ? "success" : "default" %>">
              <%= user.status.humanize %>
            </span>
          </td>
          <td>
            <% if user.admin? %><span class="badge badge--info">Admin</span><% end %>
            <% if user.disabled_at.present? %><span class="badge badge--danger">Disabled</span><% end %>
          </td>
          <td class="data-cell"><%= user.passkey_credentials.count %></td>
          <td>
            <% if application.present? %>
              <span class="badge badge--<%= application.status == "submitted" ? "warning" : "default" %>">
                <%= application.status.humanize %>
              </span>
              <% if application.first_name.present? || application.last_name.present? %>
                <%= [application.first_name, application.last_name].compact_blank.join(" ") %>
              <% end %>
            <% else %>
              <span class="detail-term">None</span>
            <% end %>
          </td>
        </tr>
```

- [ ] **Step 2: Rebuild `app/views/admin/users/show.html.erb`**

```erb
<div class="page-header">
  <h1 class="page-title"><%= @user.email_address %></h1>
  <p class="page-subtitle">Account and application management</p>
</div>

<div class="flex flex-wrap gap-2 items-center mb-6">
  <span class="badge badge--<%= @user.active_for_authentication? ? "success" : "default" %>"><%= @user.status.humanize %></span>
  <% if @user.admin? %><span class="badge badge--info">Admin</span><% end %>
  <% if @user.disabled_at.present? %><span class="badge badge--danger">Disabled</span><% end %>
  <span class="badge badge--default"><%= pluralize(@user.passkey_credentials.count, "passkey") %></span>
</div>

<div class="flex flex-wrap gap-2 mb-6">
  <%= button_to(@user.disabled_at? ? "Re-enable account" : "Disable account",
        disable_user_path(@user), method: :patch, class: "btn btn--secondary") %>
  <%= button_to(@user.admin? ? "Remove admin" : "Make admin",
        toggle_admin_user_path(@user), method: :patch, class: "btn btn--secondary") %>
  <%= button_to "Revoke all sessions",
        revoke_all_sessions_user_path(@user), method: :delete, class: "btn btn--secondary" %>
</div>

<%= render "shared/atom_marker", theme: "silo" %>
<h2 class="page-title">Membership applications</h2>

<% if @applications.any? %>
  <% @applications.each do |application| %>
    <div class="attention-card review-card <%= "review-card--pending" if application.status == "submitted" %>">
      <p class="attention-card__title">
        <span class="badge badge--<%= application.status == "submitted" ? "warning" : "default" %>">
          <%= application.status.humanize %>
        </span>
      </p>

      <dl class="detail-list mt-4">
        <dt class="detail-term">Name</dt>
        <dd class="detail-value"><%= [application.first_name, application.last_name].compact_blank.join(" ").presence || "—" %></dd>

        <dt class="detail-term">Address</dt>
        <dd class="detail-value">
          <%= [application.street, [application.city, application.state].compact_blank.join(", ")].compact_blank.join(" · ").presence || "—" %>
        </dd>

        <% if application.facebook_profile_url.present? %>
          <dt class="detail-term">Facebook profile</dt>
          <dd class="detail-value">
            <%= link_to application.facebook_profile_url, application.facebook_profile_url, target: "_blank", rel: "noopener" %>
          </dd>
        <% end %>

        <% if application.application_notes.present? %>
          <dt class="detail-term">Notes</dt>
          <dd class="detail-value detail-value--preserve"><%= application.application_notes %></dd>
        <% end %>

        <dt class="detail-term"><%= application.submitted_at.present? ? "Submitted" : "Created" %></dt>
        <dd class="detail-value"><%= l(application.submitted_at || application.created_at, format: :long) %></dd>

        <% if application.reviewed_at.present? %>
          <dt class="detail-term">Reviewed</dt>
          <dd class="detail-value"><%= l(application.reviewed_at, format: :long) %></dd>
        <% end %>

        <% if application.rejection_reason.present? %>
          <dt class="detail-term">Rejection reason</dt>
          <dd class="detail-value"><%= application.rejection_reason %></dd>
        <% end %>
      </dl>

      <% if application.status == "submitted" %>
        <div class="review-card__actions">
          <%= form_with url: reject_user_path(@user), method: :patch, class: "flex gap-2 items-center flex-wrap" do |form| %>
            <div class="form-group review-card__reason">
              <%= form.label :rejection_reason, "Rejection reason", class: "form-label" %>
              <%= form.text_field :rejection_reason, class: "form-input" %>
            </div>
            <%= form.submit "Reject", class: "btn btn--danger" %>
          <% end %>

          <%= button_to "Approve application", approve_user_path(@user), method: :patch, class: "btn btn--primary" %>
        </div>
      <% end %>
    </div>
  <% end %>
<% else %>
  <div class="empty-state">No membership applications for this account.</div>
<% end %>

<%= render "shared/atom_marker", theme: "silo" %>
<h2 class="page-title">Session history</h2>

<% if @sessions.any? %>
  <div class="table-wrapper">
    <table>
      <thead>
        <tr>
          <th>Status</th>
          <th>IP address</th>
          <th>Device</th>
          <th>Signed in</th>
          <th>Last seen</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <% @sessions.each do |session| %>
          <tr>
            <td>
              <span class="badge badge--<%= session.inactive? ? "default" : "success" %>">
                <%= session.inactive? ? "Inactive" : "Active" %>
              </span>
            </td>
            <td class="data-cell"><%= session.ip_address %></td>
            <td class="truncate-cell" title="<%= session.user_agent %>"><%= session.user_agent %></td>
            <td class="data-cell"><%= l(session.created_at, format: :long) %></td>
            <td class="data-cell"><%= session.last_seen_at ? l(session.last_seen_at, format: :long) : "—" %></td>
            <td>
              <%= button_to "Revoke",
                    revoke_session_user_path(@user, session_id: session.id),
                    method: :delete, class: "btn btn--danger btn--sm" %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
<% else %>
  <div class="empty-state">No sessions recorded for this account.</div>
<% end %>
```

- [ ] **Step 3: Run the tests**

Run: `bin/rails test test/controllers/admin/users_controller_test.rb`
Expected: PASS. If assertions pin raw strings like `"Present"` or an un-humanized status, update them to match the new chip markup.

- [ ] **Step 4: Commit**

```bash
git add app/views/admin/users test
git commit -m "style: rebuild admin account management to Silo standard

Replaces unstyled heading/list dumps with attention cards for
application review and a real table for session history. Timestamps are
localized and statuses render as chips."
```

---

### Task 8: Phantom class sweep and full verification

**Files:**
- Modify: any branch view still carrying a non-existent utility class.

- [ ] **Step 1: Sweep for phantom classes**

Run this against every view the branch touched:

```bash
git diff --name-only master...HEAD -- 'app/views/**' | xargs grep -nE \
  'space-y-|lg:grid-cols|md:flex-row|md:items-|md:justify-|gap-3|[^-]p-4|font-semibold|min-w-0|break-all|whitespace-pre-wrap|rounded-lg|border-dashed|text-\[|bg-\[|border-\[|tracking-\['
```

Expected: no output. Any hit must be replaced with a real class from Task 1 or an existing component.

- [ ] **Step 2: Confirm no undefined type tokens were introduced**

```bash
git diff master...HEAD -- app/assets/stylesheets/application.css | grep -n 'var(--text-'
```

Expected: no output (new CSS uses `--font-size-*` only).

- [ ] **Step 3: Run the full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors. Baseline was 1280 runs / 1 skip.

- [ ] **Step 4: Run the linter**

Run: `bin/rubocop`
Expected: no offenses detected.

- [ ] **Step 5: Visual verification in a real browser**

Start the server bound to `0.0.0.0` (this machine is accessed remotely):

```bash
bin/dev
```

Walk the whole flow and capture a screenshot of each page at desktop (1280px) and mobile (390px) widths:

1. `/session/new` — sign in
2. the magic-link interstitial
3. `/applications/new` — step 1
4. the application edit form — step 2
5. `/settings/profile` — Account → Profile tab
6. `/settings/security` — Account → Security tab, both with and without a passkey
7. the passkey reminder banner
8. `/admin/users` — index
9. `/admin/users/:id` — show, with a submitted application present

Confirm on each: no unstyled elements, no horizontal overflow at 390px, section headers and metadata in the right typefaces, and the Silo pages free of Living Room motifs.

- [ ] **Step 6: Report the out-of-scope finding**

Report to the user (do not fix in this branch): roughly 18 remaining `var(--text-*)` references elsewhere in `application.css` are undefined tokens and silently render at inherited font size. Affected areas are outside this branch's surface and fixing them warrants its own change with its own visual verification.

- [ ] **Step 7: Commit any sweep fixes**

```bash
git add -A
git commit -m "style: remove remaining no-op utility classes"
```

## Self-Review

**Spec coverage:** Spec section A → Tasks 1–3. Section B → Tasks 1 and 4. Section C → Tasks 1 and 5. Section D → Task 6. Section E → Tasks 1 and 7. Section F (sweep) → Task 8. Verification → Task 8 steps 3–5. All covered.

**Placeholder scan:** No TBD/TODO. Every code step carries literal code.

**Type consistency:** `#setStatus(message, state)` defined in Task 4 step 2 and called with that arity in step 3. `.auth-status` element created in Tasks 2 and 5 matches the classes toggled in Task 4. `.detail-term`/`.detail-value` defined in Task 1 and used in Tasks 5 and 7. `.review-card`/`.data-cell`/`.truncate-cell` defined in Task 1 and used in Task 7. `settings/_tabs` takes a `current:` local, passed by both callers in Task 5.

**Known test updates required:** `sessions_controller_test.rb:17` (Task 2, planned). `application_layout_auth_state_test.rb` and `admin/users_controller_test.rb` may need assertion updates (Tasks 5–7, conditional — verify before editing).
