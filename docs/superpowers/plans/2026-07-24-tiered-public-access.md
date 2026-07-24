# Tiered Public Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the site two admin-switchable access modes — `open` (fully public, as `master` behaved) and `gated` (anonymous visitors get a teaser tier) — and restore the pages the auth branch accidentally locked behind a login.

**Architecture:** A `SiteSetting` singleton row holds `access_mode`. A `SiteAccess` controller concern exposes `gated_for_visitor?` to views. Two view primitives — a `teaser` helper and a `shared/_gate` partial — are the only places gating logic lives. Routing is identical in both modes: public controllers always allow unauthenticated access, and only the amount rendered changes.

**Tech Stack:** Rails 8.1, Ruby 4.0, Minitest, Propshaft (no asset build step), hand-written `application.css`, Loops for transactional email.

## Global Constraints

- **Withheld text is never rendered.** Not `display: none`, not CSS-blurred, not `aria-hidden`. If a visitor may not read it, it must not appear in the response body. Every gated surface gets a test asserting a known phrase is *absent*.
- **Gating branches on `gated_for_visitor?` only.** Views may branch on that predicate to choose what to render, and must call `teaser(...)` and `render "shared/gate"` rather than reimplementing truncation or hand-rolling a sign-in card. Views must never call `authenticated?`, `Current.user`, or `SiteSetting` directly — the predicate is the single seam.
- **Routing never depends on mode.** No page redirects based on `access_mode`; only rendering changes.
- **Default `access_mode` is `open`.** A fresh database and an existing deployment both stay public until someone flips the switch.
- **Admin surfaces are unaffected by `access_mode`** — they stay behind `Admin::BaseController` in both modes.
- **All colors via CSS custom properties**, never hardcoded hex (`docs/plans/2026-03-28-atomic-design-system-spec.md`).
- **Typography roles:** Outfit (`--font-display`, uppercase headings), Space Grotesk (`--font-body`, prose and buttons), DM Mono (`--font-data`, metadata, uppercase + wide tracking).
- **Style:** RuboCop Rails Omakase. Run `bin/rubocop` before every commit.

## File Structure

**Stage 1 — access mode foundation**
- Create `db/migrate/<ts>_create_site_settings.rb` — table plus the initial row
- Create `app/models/site_setting.rb` — singleton, mode predicates
- Modify `app/models/current.rb` — add `site_access_mode` attribute for per-request memoization
- Create `app/controllers/concerns/site_access.rb` — `gated_for_visitor?`, exposed as a helper
- Modify `app/controllers/application_controller.rb` — include the concern
- Modify five public controllers — restore `allow_unauthenticated_access`
- Create `app/controllers/admin/site_settings_controller.rb` — the toggle
- Create `app/views/admin/site_settings/show.html.erb` — toggle UI
- Modify `config/routes.rb`, `app/views/admin/dashboard/show.html.erb`

**Stage 2 — teaser primitives**
- Create `app/helpers/access_helper.rb` — `teaser(text, chars:, fade:)`
- Create `app/views/shared/_gate.html.erb` — the sign-in card
- Modify `app/assets/stylesheets/application.css` — `.teaser-fade`, `.gate-card`
- Modify `app/views/meetings/show.html.erb` — first gated surface

**Stage 3 — card surfaces**
- Modify `app/views/meetings/_meeting_card.html.erb`, `app/views/topics/_topic_card.html.erb`
- Modify `app/views/topics/index.html.erb` — two-card cap

**Stage 4 — detail surfaces**
- Modify `app/views/topics/show.html.erb`, `app/views/committees/show.html.erb`, `app/views/members/show.html.erb`

**Stage 5 — always-email sign-in**
- Modify `app/services/transactional_email.rb`, `app/controllers/sessions_controller.rb`
- Create `app/models/sign_in_attempt.rb` and its migration — per-address throttle

---

# Stage 1 — Access Mode Foundation

Ends with: the five broken pages reachable again, the switch present, nothing teased yet.

### Task 1: SiteSetting model

**Files:**
- Create: `db/migrate/<timestamp>_create_site_settings.rb`
- Create: `app/models/site_setting.rb`
- Test: `test/models/site_setting_test.rb`

**Interfaces:**
- Consumes: nothing
- Produces: `SiteSetting.access_mode → "open" | "gated"`, `SiteSetting.gated? → Boolean`, `SiteSetting.instance → SiteSetting`, constant `SiteSetting::ACCESS_MODES`

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/site_setting_test.rb
require "test_helper"

class SiteSettingTest < ActiveSupport::TestCase
  test "defaults to open when no row exists" do
    SiteSetting.delete_all

    assert_equal "open", SiteSetting.access_mode
    assert_not SiteSetting.gated?
  end

  test "reading does not create a row" do
    SiteSetting.delete_all

    SiteSetting.access_mode

    assert_equal 0, SiteSetting.count
  end

  test "gated? reflects the stored mode" do
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)

    assert SiteSetting.gated?
  end

  test "rejects an unknown access mode" do
    setting = SiteSetting.new(access_mode: "sideways", singleton_guard: 0)

    assert_not setting.valid?
    assert_includes setting.errors[:access_mode], "is not included in the list"
  end

  test "a second row is rejected" do
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "open", singleton_guard: 0)

    assert_raises(ActiveRecord::RecordNotUnique) do
      SiteSetting.insert!({ access_mode: "gated", singleton_guard: 0 })
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/site_setting_test.rb`
Expected: FAIL with `NameError: uninitialized constant SiteSetting`

- [ ] **Step 3: Write the migration**

Generate the file with `bin/rails generate migration CreateSiteSettings`, then replace its contents:

```ruby
class CreateSiteSettings < ActiveRecord::Migration[8.1]
  def up
    create_table :site_settings do |t|
      t.string :access_mode, null: false, default: "open"
      t.integer :singleton_guard, null: false, default: 0
      t.timestamps
    end

    add_index :site_settings, :singleton_guard, unique: true

    # Seed explicitly so the intent is visible in the schema rather than
    # implied by a column default.
    execute <<~SQL
      INSERT INTO site_settings (access_mode, singleton_guard, created_at, updated_at)
      VALUES ('open', 0, NOW(), NOW())
    SQL
  end

  def down
    drop_table :site_settings
  end
end
```

- [ ] **Step 4: Write the model**

```ruby
# app/models/site_setting.rb
class SiteSetting < ApplicationRecord
  ACCESS_MODES = %w[open gated].freeze

  validates :access_mode, inclusion: { in: ACCESS_MODES }
  validates :singleton_guard, inclusion: { in: [ 0 ] }

  # Never creates. A missing row falls back to the default rather than
  # writing during a GET.
  def self.instance
    first || new(access_mode: "open", singleton_guard: 0)
  end

  def self.access_mode
    instance.access_mode
  end

  def self.gated?
    access_mode == "gated"
  end
end
```

- [ ] **Step 5: Migrate and run the tests**

Run: `bin/rails db:migrate && bin/rails test test/models/site_setting_test.rb`
Expected: PASS, 5 runs

- [ ] **Step 6: Commit**

```bash
bin/rubocop
git add db/migrate db/schema.rb app/models/site_setting.rb test/models/site_setting_test.rb
git commit -m "feat: add SiteSetting singleton with access mode"
```

---

### Task 2: Per-request access predicate

**Files:**
- Modify: `app/models/current.rb`
- Create: `app/controllers/concerns/site_access.rb`
- Modify: `app/controllers/application_controller.rb:1-13`
- Test: `test/controllers/site_access_test.rb`

**Interfaces:**
- Consumes: `SiteSetting.access_mode` (Task 1)
- Produces: `gated_for_visitor? → Boolean`, available in controllers and as a view helper. True only when the mode is `gated` **and** the visitor is not authenticated.

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/site_access_test.rb
require "test_helper"

class SiteAccessTest < ActionDispatch::IntegrationTest
  test "anonymous visitor is gated when the mode is gated" do
    set_access_mode("gated")

    get root_path

    assert_response :success
    assert @controller.send(:gated_for_visitor?)
  end

  test "anonymous visitor is not gated when the mode is open" do
    set_access_mode("open")

    get root_path

    assert_not @controller.send(:gated_for_visitor?)
  end

  test "authenticated member is never gated" do
    set_access_mode("gated")
    user = User.create!(email_address: "member@example.com", status: "active")
    sign_in_as(user)

    get root_path

    assert_not @controller.send(:gated_for_visitor?)
  end

  # No etag test. Verified empirically that Rails' must-revalidate default plus
  # Rack::ETag's body-derived validator already prevent a stale page surviving a
  # mode flip — see security invariant 4 in the design spec.

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
```

If `sign_in_as` does not already exist in `test/test_helper.rb`, use the same
helper the existing session tests use — check `test/controllers/sessions_controller_test.rb`
for the established pattern and reuse it verbatim rather than inventing a new one.

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/site_access_test.rb`
Expected: FAIL with `NoMethodError: undefined method 'gated_for_visitor?'`

- [ ] **Step 3: Add the Current attribute**

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :site_access_mode
  delegate :user, to: :session, allow_nil: true
end
```

- [ ] **Step 4: Write the concern**

```ruby
# app/controllers/concerns/site_access.rb
module SiteAccess
  extend ActiveSupport::Concern

  included do
    helper_method :gated_for_visitor?, :site_gated?
  end

  private

    # Memoized per request. CurrentAttributes is reset between requests, so
    # this is one query per request rather than one per call site.
    def site_gated?
      Current.site_access_mode ||= SiteSetting.access_mode
      Current.site_access_mode == "gated"
    end

    def gated_for_visitor?
      site_gated? && !authenticated?
    end
end
```

- [ ] **Step 5: Include it in ApplicationController**

Add `include SiteAccess` immediately after `include Authentication`:

```ruby
class ApplicationController < ActionController::Base
  include Pagy::Method
  include Authentication
  include SiteAccess
```

- [ ] **Step 6: Run the tests**

Run: `bin/rails test test/controllers/site_access_test.rb`
Expected: PASS, 3 runs

- [ ] **Step 7: Commit**

```bash
bin/rubocop
git add app/models/current.rb app/controllers/concerns/site_access.rb app/controllers/application_controller.rb test/controllers/site_access_test.rb
git commit -m "feat: add per-request gated_for_visitor predicate"
```

---

### Task 3: Restore public reachability

**Files:**
- Modify: `app/controllers/topics_controller.rb:1`, `app/controllers/meetings_controller.rb:1`, `app/controllers/committees_controller.rb:1`, `app/controllers/members_controller.rb:1`, `app/controllers/og_controller.rb:1`
- Test: `test/controllers/public_reachability_test.rb`

**Interfaces:**
- Consumes: nothing
- Produces: every public page returns 200 to an anonymous visitor in both modes

This is the task that un-breaks the site. It is independently shippable.

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/public_reachability_test.rb
require "test_helper"

class PublicReachabilityTest < ActionDispatch::IntegrationTest
  MODES = %w[open gated].freeze

  test "index pages are reachable anonymously in both modes" do
    MODES.each do |mode|
      set_access_mode(mode)

      [ root_path, topics_path, meetings_path, committees_path ].each do |path|
        get path
        assert_response :success, "#{path} should render anonymously in #{mode} mode"
      end
    end
  end

  test "detail pages are reachable anonymously in both modes" do
    meeting = Meeting.create!(body_name: "City Council Meeting", starts_at: 2.days.ago)
    topic = Topic.create!(name: "Reachability Topic", status: "approved")

    MODES.each do |mode|
      set_access_mode(mode)

      get meeting_path(meeting)
      assert_response :success, "meeting show should render anonymously in #{mode} mode"

      get topic_path(topic)
      assert_response :success, "topic show should render anonymously in #{mode} mode"
    end
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/public_reachability_test.rb`
Expected: FAIL — responses are `302` redirects to `/session/new`

- [ ] **Step 3: Restore unauthenticated access on all five controllers**

Add this line directly beneath the `class` declaration and any `include` lines in each of the five controllers:

```ruby
allow_unauthenticated_access
```

For example, `app/controllers/topics_controller.rb` becomes:

```ruby
class TopicsController < ApplicationController
  include HighlightSignals
  include LoadsGeneratedImages

  allow_unauthenticated_access
```

Apply the identical line to `meetings_controller.rb`, `committees_controller.rb`,
`members_controller.rb`, and `og_controller.rb`.

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/controllers/public_reachability_test.rb`
Expected: PASS, 2 runs

- [ ] **Step 5: Verify no public controller is still gated**

Run:

```bash
for f in app/controllers/*.rb; do
  n=$(basename "$f")
  [ "$n" = "application_controller.rb" ] && continue
  command grep -q "allow_unauthenticated_access" "$f" || echo "STILL GATED: $n"
done
```

Expected: no output.

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: no new failures against the pre-task baseline

- [ ] **Step 7: Commit**

```bash
bin/rubocop
git add app/controllers test/controllers/public_reachability_test.rb
git commit -m "fix: restore anonymous access to public pages"
```

---

### Task 4: Admin toggle

**Files:**
- Create: `app/controllers/admin/site_settings_controller.rb`
- Create: `app/views/admin/site_settings/show.html.erb`
- Modify: `config/routes.rb:46` (inside the existing `scope :admin do` block)
- Modify: `app/views/admin/dashboard/show.html.erb`
- Test: `test/controllers/admin/site_settings_controller_test.rb`

**Interfaces:**
- Consumes: `SiteSetting` (Task 1)
- Produces: `admin_site_settings_path` (GET show, PATCH update)

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/admin/site_settings_controller_test.rb
require "test_helper"

class Admin::SiteSettingsControllerTest < ActionDispatch::IntegrationTest
  test "admin can switch the site to gated" do
    sign_in_as_admin(create_passkey_admin)
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "open", singleton_guard: 0)

    patch admin_site_settings_path, params: { site_setting: { access_mode: "gated" } }

    assert_redirected_to admin_site_settings_path
    assert_equal "gated", SiteSetting.access_mode
  end

  test "an unknown mode is rejected and the current mode survives" do
    sign_in_as_admin(create_passkey_admin)
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "open", singleton_guard: 0)

    patch admin_site_settings_path, params: { site_setting: { access_mode: "sideways" } }

    assert_response :unprocessable_entity
    assert_equal "open", SiteSetting.access_mode
  end

  test "non-admins cannot reach the toggle" do
    get admin_site_settings_path

    assert_response :redirect
  end

  private

    def create_passkey_admin
      user = User.create!(email_address: "settings-admin@example.com", admin: true, status: "active")
      user.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "public-key", sign_count: 0)
      user
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/site_settings_controller_test.rb`
Expected: FAIL with `NameError: undefined local variable or method 'admin_site_settings_path'`

- [ ] **Step 3: Add the route**

Inside the existing `scope :admin do` block in `config/routes.rb`:

```ruby
resource :site_settings, only: %i[show update], controller: "admin/site_settings", as: :admin_site_settings
```

- [ ] **Step 4: Write the controller**

```ruby
# app/controllers/admin/site_settings_controller.rb
module Admin
  class SiteSettingsController < BaseController
    def show
      @site_setting = SiteSetting.instance
    end

    def update
      @site_setting = SiteSetting.instance

      if @site_setting.update(site_setting_params)
        redirect_to admin_site_settings_path, notice: "Access mode is now #{@site_setting.access_mode}."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

      def site_setting_params
        params.expect(site_setting: [ :access_mode ])
      end
  end
end
```

- [ ] **Step 5: Write the view**

```erb
<%# app/views/admin/site_settings/show.html.erb %>
<div class="page-header">
  <h1 class="page-title">Site access</h1>
  <p class="page-subtitle">Who can read the site without an account</p>
</div>

<% if flash[:notice] %>
  <div class="flash flash--success"><%= flash[:notice] %></div>
<% end %>

<div class="section-header">
  <%= render "shared/atom_marker", theme: "silo" %>
  <span class="section-header__label">Access mode</span>
  <div class="section-header__line"></div>
</div>

<%= form_with model: @site_setting, url: admin_site_settings_path, method: :patch do |form| %>
  <% if @site_setting.errors.any? %>
    <div class="flash flash--danger">
      <ul>
        <% @site_setting.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div class="form-group">
    <label class="form-label" for="site_setting_access_mode_open">
      <%= form.radio_button :access_mode, "open", id: "site_setting_access_mode_open" %>
      Open — anyone can read everything
    </label>
    <p class="form-hint">The site behaves as a fully public civic resource.</p>
  </div>

  <div class="form-group">
    <label class="form-label" for="site_setting_access_mode_gated">
      <%= form.radio_button :access_mode, "gated", id: "site_setting_access_mode_gated" %>
      Gated — anonymous visitors see a preview only
    </label>
    <p class="form-hint">Summaries, briefings, and voting records require an approved account.</p>
  </div>

  <%= form.submit "Save access mode", class: "btn btn--primary" %>
<% end %>
```

- [ ] **Step 6: Link it from the admin dashboard**

Add to `app/views/admin/dashboard/show.html.erb`, following the link style already used there:

```erb
<%= link_to "Site access", admin_site_settings_path, class: "btn btn--secondary" %>
```

- [ ] **Step 7: Run the tests**

Run: `bin/rails test test/controllers/admin/site_settings_controller_test.rb`
Expected: PASS, 3 runs

- [ ] **Step 8: Commit**

```bash
bin/rubocop
git add app/controllers/admin/site_settings_controller.rb app/views/admin/site_settings config/routes.rb app/views/admin/dashboard/show.html.erb test/controllers/admin/site_settings_controller_test.rb
git commit -m "feat: add admin toggle for site access mode"
```

---

# Stage 2 — Teaser Primitives, Proven on Meeting Show

Ends with: the pattern established and visually verified on the richest surface.

### Task 5: The teaser helper

**Files:**
- Create: `app/helpers/access_helper.rb`
- Test: `test/helpers/access_helper_test.rb`

**Interfaces:**
- Consumes: `gated_for_visitor?` (Task 2)
- Produces: `teaser(text, chars:, fade: :block) → SafeBuffer` — returns the full text unwrapped when not gated; returns a `<span class="teaser-fade">` (or `teaser-fade--inline`) containing text truncated at a word boundary when gated.

- [ ] **Step 1: Write the failing test**

```ruby
# test/helpers/access_helper_test.rb
require "test_helper"

class AccessHelperTest < ActionView::TestCase
  include AccessHelper

  test "returns full text untouched when not gated" do
    stub_gated(false)

    result = teaser("The quick brown fox jumps over the lazy dog", chars: 10)

    assert_equal "The quick brown fox jumps over the lazy dog", result
    assert_no_match(/teaser-fade/, result)
  end

  test "truncates at a word boundary when gated" do
    stub_gated(true)

    result = teaser("The quick brown fox jumps over the lazy dog", chars: 15)

    assert_match(/teaser-fade/, result)
    assert_match(/The quick/, result)
    assert_no_match(/lazy dog/, result)
  end

  test "does not append an ellipsis" do
    stub_gated(true)

    result = teaser("The quick brown fox jumps over the lazy dog", chars: 15)

    assert_no_match(/\.\.\./, result)
    assert_no_match(/…/, result)
  end

  test "leaves short text intact but still marks it faded" do
    stub_gated(true)

    result = teaser("Short", chars: 100)

    assert_match(/Short/, result)
  end

  test "returns nil for blank text" do
    stub_gated(true)

    assert_nil teaser(nil, chars: 10)
    assert_nil teaser("", chars: 10)
  end

  test "inline fade uses the inline modifier class" do
    stub_gated(true)

    result = teaser("The quick brown fox jumps over the lazy dog", chars: 15, fade: :inline)

    assert_match(/teaser-fade--inline/, result)
  end

  test "escapes markup in the source text" do
    stub_gated(true)

    result = teaser("<script>alert(1)</script> and more words here", chars: 200)

    assert_no_match(/<script>/, result)
    assert_match(/&lt;script&gt;/, result)
  end

  private

    def stub_gated(value)
      @gated = value
    end

    def gated_for_visitor?
      @gated
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/helpers/access_helper_test.rb`
Expected: FAIL with `NameError: uninitialized constant AccessHelper`

- [ ] **Step 3: Write the helper**

```ruby
# app/helpers/access_helper.rb
module AccessHelper
  # Renders as much of `text` as an anonymous visitor is allowed to see.
  #
  # The withheld remainder is never placed in the response — the fade is a
  # visual disguise for the truncation point, not a concealment mechanism.
  #
  # fade: :block  — vertical gradient, for multi-line prose
  # fade: :inline — horizontal gradient, for single-line card headlines
  def teaser(text, chars:, fade: :block)
    return nil if text.blank?
    return text unless gated_for_visitor?

    visible = text.to_s.truncate(chars, separator: " ", omission: "")
    modifier = fade == :inline ? " teaser-fade--inline" : ""

    tag.span(visible, class: "teaser-fade#{modifier}")
  end
end
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/helpers/access_helper_test.rb`
Expected: PASS, 7 runs

- [ ] **Step 5: Commit**

```bash
bin/rubocop
git add app/helpers/access_helper.rb test/helpers/access_helper_test.rb
git commit -m "feat: add teaser helper for truncated anonymous content"
```

---

### Task 6: The gate card

**Files:**
- Create: `app/views/shared/_gate.html.erb`
- Modify: `app/assets/stylesheets/application.css` (append)

**Interfaces:**
- Consumes: `new_public_session_path`, `new_application_path` (existing routes)
- Produces: `render "shared/gate"` and `render "shared/gate", message: "..."` — a sign-in card with two actions. Renders the default message when `message` is omitted.

- [ ] **Step 1: Write the partial**

```erb
<%# app/views/shared/_gate.html.erb
    Locals: message (optional) — the headline shown above the two actions. %>
<% message = local_assigns.fetch(:message, "Sign in to keep reading") %>
<div class="gate-card">
  <p class="gate-card__title"><%= message %></p>
  <p class="gate-card__meta">Access is by approval</p>
  <div class="gate-card__actions">
    <%= link_to "Sign in", new_public_session_path, class: "btn btn--primary btn--sm" %>
    <%= link_to "Request access →", new_application_path, class: "btn btn--secondary btn--sm" %>
  </div>
</div>
```

- [ ] **Step 2: Append the CSS**

Append to `app/assets/stylesheets/application.css`. Use `command grep -n "teaser-fade" app/assets/stylesheets/application.css` first to confirm these classes do not already exist.

```css
/* ==========================================================================
   Tiered access — teaser fade and gate card
   The fade disguises a server-side truncation point. It never conceals text;
   withheld content is not rendered at all.
   ========================================================================== */

.teaser-fade {
  display: inline-block;
  -webkit-mask-image: linear-gradient(to bottom, var(--color-text) 45%, transparent 100%);
  mask-image: linear-gradient(to bottom, var(--color-text) 45%, transparent 100%);
}

.teaser-fade--inline {
  -webkit-mask-image: linear-gradient(to right, var(--color-text) 65%, transparent 100%);
  mask-image: linear-gradient(to right, var(--color-text) 65%, transparent 100%);
}

.gate-card {
  margin: var(--space-6) 0;
  padding: var(--space-6);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-left: 4px solid var(--color-teal);
  border-radius: var(--radius-md);
  text-align: center;
}

.gate-card__title {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: var(--font-size-lg);
  text-transform: uppercase;
  letter-spacing: -0.01em;
  color: var(--color-teal);
  margin: 0;
}

.gate-card__meta {
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--color-text-secondary);
  margin: var(--space-2) 0 0;
}

.gate-card__actions {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
  justify-content: center;
  margin-top: var(--space-4);
}
```

- [ ] **Step 3: Verify every custom property used above is defined**

Run:

```bash
for v in --color-text --color-surface --color-border --color-teal --color-text-secondary \
         --font-display --font-data --font-size-lg --font-size-xs \
         --space-2 --space-4 --space-6 --radius-md; do
  command grep -q -- "$v:" app/assets/stylesheets/application.css || echo "UNDEFINED: $v"
done
```

Expected: no output. If any token is reported undefined, find the correct name
in `docs/plans/2026-03-28-atomic-design-system-spec.md` and fix the CSS before
continuing — an undefined token fails silently.

- [ ] **Step 4: Commit**

```bash
bin/rubocop
git add app/views/shared/_gate.html.erb app/assets/stylesheets/application.css
git commit -m "feat: add gate card partial and teaser fade styling"
```

---

### Task 7: Gate the meeting show page

**Files:**
- Modify: `app/views/meetings/show.html.erb:94-125`
- Test: `test/controllers/meetings_gating_test.rb`

**Interfaces:**
- Consumes: `teaser` (Task 5), `shared/_gate` (Task 6), `gated_for_visitor?` (Task 2)
- Produces: the reference pattern that Stages 3 and 4 repeat

Anonymous visitors keep the header, image, and lede in full; the first Key
Decision is teased at 240 characters; everything below is not rendered.

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/meetings_gating_test.rb
require "test_helper"

class MeetingsGatingTest < ActionDispatch::IntegrationTest
  WITHHELD = "Council directed staff to renegotiate the lakefront parking easement".freeze

  setup do
    @meeting = Meeting.create!(body_name: "City Council Meeting", starts_at: 3.days.ago)
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "headline" => "Council approved the Washington Street reconstruction contract.",
        "highlights" => [ { "text" => WITHHELD } ]
      }
    )
  end

  test "anonymous visitor never receives the withheld text" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    assert_response :success
    assert_no_match(/#{Regexp.escape(WITHHELD)}/, response.body)
  end

  test "anonymous visitor sees the lede and a gate" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    assert_match(/Washington Street reconstruction/, response.body)
    assert_match(/Sign in to keep reading/, response.body)
  end

  test "signed-in member receives the full page" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "reader@example.com", status: "active"))

    get meeting_path(@meeting)

    assert_match(/#{Regexp.escape(WITHHELD)}/, response.body)
    assert_no_match(/Sign in to keep reading/, response.body)
  end

  test "open mode shows everything to anonymous visitors" do
    set_access_mode("open")

    get meeting_path(@meeting)

    assert_match(/#{Regexp.escape(WITHHELD)}/, response.body)
    assert_no_match(/Sign in to keep reading/, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/meetings_gating_test.rb`
Expected: FAIL — the withheld text is present in the anonymous response

- [ ] **Step 3: Gate the view**

In `app/views/meetings/show.html.erb`, the lede block currently ends at the
`<% end %>` following the `section-empty` fallback (around line 105). Immediately
after that block, wrap the remainder of the summary content.

Replace the Key Decisions section opening so the first decision is teased and the
rest is withheld:

```erb
    <%# === Key Decisions === %>
    <% highlights = meeting_highlights(gd) %>
    <% if gated_for_visitor? %>
      <% first_highlight = highlights.first %>
      <% if first_highlight.present? %>
        <section class="meeting-article-section">
          <div class="home-section-header">
            <%= render "shared/atom_marker" %>
            <span class="section-label">Key Decisions</span>
            <span class="section-line"></span>
          </div>
          <div class="meeting-decisions">
            <div class="meeting-decision">
              <p class="meeting-decision-text"><%= teaser(first_highlight["text"], chars: 240) %></p>
            </div>
          </div>
        </section>
      <% end %>
      <%= render "shared/gate" %>
    <% else %>
      <% if highlights.any? %>
```

Then, at the end of the existing page content, close the `else` branch with a
matching `<% end %>`. The structure is:

```erb
<% if gated_for_visitor? %>
  ... teased first decision, then the gate ...
<% else %>
  ... every existing section, unchanged ...
<% end %>
```

Nothing inside the `else` branch changes. The point of this shape is that the
gated branch renders a deliberately small subset rather than hiding parts of the
full branch.

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/controllers/meetings_gating_test.rb`
Expected: PASS, 4 runs

- [ ] **Step 5: Verify in a browser**

Start the server, then load a real meeting anonymously in `gated` mode and confirm:
the lede reads normally, the first decision fades out mid-sentence, the gate card
sits below it, and nothing further appears.

```bash
bin/rails runner 'SiteSetting.instance.update!(access_mode: "gated")'
bin/dev -b 0.0.0.0 -p 3005
```

Check the raw HTML too — this is the assertion that matters:

```bash
curl -s http://127.0.0.1:3005/meetings/<id> | command grep -c "renegotiate the lakefront"
```

Expected: `0`

- [ ] **Step 6: Commit**

```bash
bin/rubocop
git add app/views/meetings/show.html.erb test/controllers/meetings_gating_test.rb
git commit -m "feat: gate meeting show page below the lede"
```

---

# Stage 3 — Card Surfaces

Ends with: both index pages and both search-results views teased.

### Task 8: Meeting card headline

**Files:**
- Modify: `app/views/meetings/_meeting_card.html.erb:37-39`
- Test: `test/controllers/meetings_index_gating_test.rb`

**Interfaces:**
- Consumes: `teaser` (Task 5)
- Produces: no new interface — the shared card partial is used by the meetings index, the recent/upcoming lists, and search results, so one edit covers all four

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/meetings_index_gating_test.rb
require "test_helper"

class MeetingsIndexGatingTest < ActionDispatch::IntegrationTest
  HEADLINE = "Council approved the Washington Street reconstruction contract " \
             "after residents raised concerns about driveway access during the " \
             "eighteen month build window and asked staff to return with options".freeze

  setup do
    @meeting = Meeting.create!(body_name: "City Council Meeting", starts_at: 2.days.ago)
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: { "headline" => HEADLINE }
    )
  end

  test "anonymous visitor gets only the first 90 characters of a card headline" do
    set_access_mode("gated")

    get meetings_path

    assert_response :success
    assert_match(/Council approved the Washington Street/, response.body)
    assert_no_match(/asked staff to return with options/, response.body)
    assert_match(/teaser-fade/, response.body)
  end

  test "signed-in member gets the whole headline" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "card-reader@example.com", status: "active"))

    get meetings_path

    assert_match(/asked staff to return with options/, response.body)
  end

  test "open mode shows the whole headline anonymously" do
    set_access_mode("open")

    get meetings_path

    assert_match(/asked staff to return with options/, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/meetings_index_gating_test.rb`
Expected: FAIL — the full headline is present anonymously

- [ ] **Step 3: Tease the headline**

In `app/views/meetings/_meeting_card.html.erb`, replace:

```erb
    <% if headline %>
      <p class="meetings-card-headline"><%= headline %></p>
    <% end %>
```

with:

```erb
    <% if headline %>
      <p class="meetings-card-headline"><%= teaser(headline, chars: 90, fade: :inline) %></p>
    <% end %>
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/controllers/meetings_index_gating_test.rb`
Expected: PASS, 3 runs

- [ ] **Step 5: Commit**

```bash
bin/rubocop
git add app/views/meetings/_meeting_card.html.erb test/controllers/meetings_index_gating_test.rb
git commit -m "feat: tease meeting card headlines for anonymous visitors"
```

---

### Task 9: Topic card headline

**Files:**
- Modify: `app/views/topics/_topic_card.html.erb:25-27`
- Test: `test/controllers/topics_card_gating_test.rb`

**Interfaces:**
- Consumes: `teaser` (Task 5)
- Produces: no new interface — covers the topics index hero, the topics list, the meeting show "Issues in This Meeting" section, and topic search results

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/topics_card_gating_test.rb
require "test_helper"

class TopicsCardGatingTest < ActionDispatch::IntegrationTest
  HEADLINE = "The council is weighing a stormwater utility fee that would add a " \
             "monthly charge to every household water bill starting next spring".freeze

  setup do
    @topic = Topic.create!(name: "Stormwater Utility Fee", status: "approved", resident_impact_score: 5)
    @topic.create_topic_briefing!(headline: HEADLINE, generation_tier: "headline_only")
  end

  test "anonymous visitor gets a truncated topic headline" do
    set_access_mode("gated")

    get topics_path

    assert_response :success
    assert_match(/teaser-fade/, response.body)
    assert_no_match(/starting next spring/, response.body)
  end

  test "signed-in member gets the whole headline" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "topic-reader@example.com", status: "active"))

    get topics_path

    assert_match(/starting next spring/, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/topics_card_gating_test.rb`
Expected: FAIL — the full headline is present anonymously

- [ ] **Step 3: Tease the headline**

In `app/views/topics/_topic_card.html.erb`, replace:

```erb
    <% if topic.topic_briefing&.headline.present? %>
      <p class="topics-card-headline"><%= topic.topic_briefing.headline %></p>
    <% end %>
```

with:

```erb
    <% if topic.topic_briefing&.headline.present? %>
      <p class="topics-card-headline"><%= teaser(topic.topic_briefing.headline, chars: 90, fade: :inline) %></p>
    <% end %>
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/controllers/topics_card_gating_test.rb`
Expected: PASS, 2 runs

- [ ] **Step 5: Commit**

```bash
bin/rubocop
git add app/views/topics/_topic_card.html.erb test/controllers/topics_card_gating_test.rb
git commit -m "feat: tease topic card headlines for anonymous visitors"
```

---

### Task 10: Two-card cap on the topics index

**Files:**
- Modify: `app/views/topics/index.html.erb:58-95`
- Test: `test/controllers/topics_index_gating_test.rb`

**Interfaces:**
- Consumes: `gated_for_visitor?` (Task 2), `shared/_gate` (Task 6)
- Produces: no new interface

Anonymous visitors see the first two hero cards and a gate. The paginated list
below is not rendered.

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/topics_index_gating_test.rb
require "test_helper"

class TopicsIndexGatingTest < ActionDispatch::IntegrationTest
  setup do
    6.times do |i|
      Topic.create!(
        name: "Gating Sample Topic #{i}",
        status: "approved",
        resident_impact_score: 5,
        last_activity_at: i.days.ago
      )
    end
  end

  test "anonymous visitor sees at most two topic cards" do
    set_access_mode("gated")

    get topics_path

    assert_response :success
    assert_operator response.body.scan(/class="topics-card/).size, :<=, 2
    assert_match(/Sign in to keep reading/, response.body)
  end

  test "signed-in member sees the full list" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "list-reader@example.com", status: "active"))

    get topics_path

    assert_operator response.body.scan(/class="topics-card/).size, :>, 2
    assert_no_match(/Sign in to keep reading/, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/topics_index_gating_test.rb`
Expected: FAIL — all cards render anonymously

- [ ] **Step 3: Cap the hero grid and replace the list**

In `app/views/topics/index.html.erb`, change the hero loop to cap at two:

```erb
      <div class="topics-hero-grid" id="hero-topics">
        <% (gated_for_visitor? ? @hero_topics.first(2) : @hero_topics).each do |topic| %>
          <%= render "topics/topic_card", topic: topic, highlight_signals: @highlight_signals %>
        <% end %>
      </div>
```

Then wrap the remaining list section so the gate replaces it entirely:

```erb
<% if gated_for_visitor? %>
  <%= render "shared/gate", message: "Sign in to see every topic" %>
<% else %>
  <%# ...the existing "All Topics" section, unchanged... %>
<% end %>
```

Apply the same treatment to the search-results branch at the top of the file:

```erb
      <div class="topics-list">
        <% (gated_for_visitor? ? @search_results.first(2) : @search_results).each do |topic| %>
          <%= render "topics/topic_card", topic: topic, highlight_signals: {} %>
        <% end %>
      </div>
      <% if gated_for_visitor? && @search_results.size > 2 %>
        <%= render "shared/gate", message: "Sign in to see all results" %>
      <% end %>
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/controllers/topics_index_gating_test.rb`
Expected: PASS, 2 runs

- [ ] **Step 5: Commit**

```bash
bin/rubocop
git add app/views/topics/index.html.erb test/controllers/topics_index_gating_test.rb
git commit -m "feat: cap the topics index at two cards for anonymous visitors"
```

---

# Stage 4 — Detail Surfaces

Ends with all eight surfaces gated and an adversarial sweep run against the real app.

### Task 11: Topic show page

**Files:**
- Modify: `app/views/topics/show.html.erb:51-53`
- Test: `test/controllers/topics_show_gating_test.rb`

**Interfaces:**
- Consumes: `gated_for_visitor?` (Task 2), `shared/_gate` (Task 6)
- Produces: no new interface

What to Watch renders in full. Everything after it is withheld.

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/topics_show_gating_test.rb
require "test_helper"

class TopicsShowGatingTest < ActionDispatch::IntegrationTest
  WATCH = "Whether the council funds the design phase this budget cycle".freeze
  WITHHELD = "Staff recommended deferring the assessment until the grant is confirmed".freeze

  setup do
    @topic = Topic.create!(name: "Stormwater Design Phase", status: "approved")
    @topic.create_topic_briefing!(
      headline: "Stormwater work is up for funding",
      generation_tier: "full",
      editorial_content: WITHHELD,
      generation_data: {
        "editorial_analysis" => { "what_to_watch" => WATCH, "current_state" => WITHHELD }
      }
    )
  end

  test "anonymous visitor sees What to Watch but nothing after it" do
    set_access_mode("gated")

    get topic_path(@topic)

    assert_response :success
    assert_match(/#{Regexp.escape(WATCH)}/, response.body)
    assert_no_match(/#{Regexp.escape(WITHHELD)}/, response.body)
    assert_match(/Sign in to keep reading/, response.body)
  end

  test "signed-in member sees the whole page" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "topic-show@example.com", status: "active"))

    get topic_path(@topic)

    assert_match(/#{Regexp.escape(WITHHELD)}/, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/topics_show_gating_test.rb`
Expected: FAIL — withheld content is present anonymously

- [ ] **Step 3: Gate everything after What to Watch**

In `app/views/topics/show.html.erb`, the What to Watch section ends with `<% end %>`
around line 51. Directly after it, insert:

```erb
  <% if gated_for_visitor? %>
    <%= render "shared/gate" %>
  <% else %>
```

and add the matching `<% end %>` at the very end of the `<article>` content,
before the closing tag. Every section from Coming Up onward sits inside the
`else` branch, unchanged.

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/controllers/topics_show_gating_test.rb`
Expected: PASS, 2 runs

- [ ] **Step 5: Commit**

```bash
bin/rubocop
git add app/views/topics/show.html.erb test/controllers/topics_show_gating_test.rb
git commit -m "feat: gate topic show page after What to Watch"
```

---

### Task 12: Committee show page

**Files:**
- Modify: `app/views/committees/show.html.erb:48-53`
- Test: `test/controllers/committees_show_gating_test.rb`

**Interfaces:**
- Consumes: `gated_for_visitor?` (Task 2), `shared/_gate` (Task 6)
- Produces: no new interface

The "What They've Been Working On" heading stays visible so a visitor knows what
they are missing; its contents and everything below are withheld.

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/committees_show_gating_test.rb
require "test_helper"

class CommitteesShowGatingTest < ActionDispatch::IntegrationTest
  WITHHELD = "Harbor dredging permit renewal".freeze

  setup do
    @committee = Committee.create!(name: "Harbor Commission", committee_type: "city", status: "active")
    topic = Topic.create!(name: WITHHELD, status: "approved", canonical_name: WITHHELD)
    meeting = Meeting.create!(body_name: "Harbor Commission Meeting", starts_at: 5.days.ago, committee: @committee)
    item = meeting.agenda_items.create!(title: "Dredging permit", order_index: 1)
    item.agenda_item_topics.create!(topic: topic)
  end

  test "anonymous visitor sees the heading but not the activity" do
    set_access_mode("gated")

    get committee_path(@committee)

    assert_response :success
    assert_match(/What They&#39;ve Been Working On|What They've Been Working On/, response.body)
    assert_no_match(/#{Regexp.escape(WITHHELD)}/, response.body)
    assert_match(/Sign in to keep reading/, response.body)
  end

  test "signed-in member sees the activity" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "committee-reader@example.com", status: "active"))

    get committee_path(@committee)

    assert_match(/#{Regexp.escape(WITHHELD)}/, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/committees_show_gating_test.rb`
Expected: FAIL — topic names are present anonymously

- [ ] **Step 3: Gate the section body**

In `app/views/committees/show.html.erb`, immediately after the `home-section-header`
div that contains the "What They've Been Working On" label, insert:

```erb
    <% if gated_for_visitor? %>
      <%= render "shared/gate" %>
    <% else %>
```

and close it with `<% end %>` at the end of that `<section>`, before `</section>`.
Everything below that section moves inside the same `else` branch.

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/controllers/committees_show_gating_test.rb`
Expected: PASS, 2 runs

- [ ] **Step 5: Commit**

```bash
bin/rubocop
git add app/views/committees/show.html.erb test/controllers/committees_show_gating_test.rb
git commit -m "feat: gate committee activity for anonymous visitors"
```

---

### Task 13: Member show page

**Files:**
- Modify: `app/views/members/show.html.erb:52-58`
- Test: `test/controllers/members_show_gating_test.rb`

**Interfaces:**
- Consumes: `gated_for_visitor?` (Task 2), `shared/_gate` (Task 6)
- Produces: no new interface

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/members_show_gating_test.rb
require "test_helper"

class MembersShowGatingTest < ActionDispatch::IntegrationTest
  WITHHELD_TOPIC = "Shoreline Setback Variance".freeze

  setup do
    @member = Member.create!(name: "Jordan Reyes")
    @committee = Committee.create!(name: "Plan Commission", committee_type: "city", status: "active")
    meeting = Meeting.create!(body_name: "Plan Commission Meeting", starts_at: 6.days.ago, committee: @committee)
    topic = Topic.create!(name: WITHHELD_TOPIC, status: "approved", canonical_name: WITHHELD_TOPIC)
    item = meeting.agenda_items.create!(title: "Variance request", order_index: 1)
    item.agenda_item_topics.create!(topic: topic)
    motion = meeting.motions.create!(description: "Approve the variance", outcome: "passed", agenda_item: item)
    motion.votes.create!(member: @member, value: "aye")
  end

  test "anonymous visitor sees the heading but no votes" do
    set_access_mode("gated")

    get member_path(@member)

    assert_response :success
    assert_match(/Voting Record/, response.body)
    assert_no_match(/#{Regexp.escape(WITHHELD_TOPIC)}/, response.body)
    assert_match(/Sign in to keep reading/, response.body)
  end

  test "signed-in member sees the voting record" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "member-reader@example.com", status: "active"))

    get member_path(@member)

    assert_match(/#{Regexp.escape(WITHHELD_TOPIC)}/, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
```

Column names verified against `db/schema.rb`: `agenda_items` uses `order_index`
(there is no `position`), `motions` carry `description` and `outcome`, `votes`
carry `member` and `value`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/members_show_gating_test.rb`
Expected: FAIL — the topic name is present anonymously

- [ ] **Step 3: Gate the section body**

In `app/views/members/show.html.erb`, immediately after the `home-section-header`
div containing the "Voting Record" label, insert:

```erb
    <% if gated_for_visitor? %>
      <%= render "shared/gate" %>
    <% else %>
```

and close it with `<% end %>` at the end of that `<section>`. Everything below
moves inside the same `else` branch.

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/controllers/members_show_gating_test.rb`
Expected: PASS, 2 runs

- [ ] **Step 5: Commit**

```bash
bin/rubocop
git add app/views/members/show.html.erb test/controllers/members_show_gating_test.rb
git commit -m "feat: gate member voting records for anonymous visitors"
```

---

### Task 14: Adversarial sweep

**Files:**
- Create: `test/controllers/anonymous_leak_sweep_test.rb`

**Interfaces:**
- Consumes: every gated surface from Tasks 7–13
- Produces: the regression net that keeps a future edit from reintroducing full text

- [ ] **Step 1: Write the sweep test**

```ruby
# test/controllers/anonymous_leak_sweep_test.rb
require "test_helper"

# One test, every gated surface. This is the net that catches a future edit
# that renders withheld text behind a CSS class instead of omitting it.
class AnonymousLeakSweepTest < ActionDispatch::IntegrationTest
  SECRET = "ZZQX_WITHHELD_CANARY_PHRASE".freeze

  setup do
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)

    @committee = Committee.create!(name: "Sweep Commission", committee_type: "city", status: "active")
    @meeting = Meeting.create!(body_name: "Sweep Commission Meeting", starts_at: 4.days.ago, committee: @committee)
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "headline" => "A routine headline that is fine to show.",
        "highlights" => [ { "text" => SECRET } ],
        "public_input" => [ { "text" => SECRET } ]
      }
    )

    # The canary must never sit in a field a gated page legitimately shows.
    # Topic name and canonical_name appear in page headers and card titles, so
    # the canary goes only in withheld body content.
    @topic = Topic.create!(name: "Sweep Topic", status: "approved", canonical_name: "Sweep Topic")
    @topic.create_topic_briefing!(
      headline: "A routine headline that is fine to show.",
      generation_tier: "full",
      editorial_content: SECRET,
      generation_data: { "editorial_analysis" => { "current_state" => SECRET } }
    )
  end

  test "no gated surface leaks the canary to an anonymous visitor" do
    paths = [
      root_path,
      topics_path,
      meetings_path,
      committees_path,
      topic_path(@topic),
      meeting_path(@meeting),
      committee_path(@committee),
      topics_path(q: "Sweep"),
      meetings_path(q: "Sweep")
    ]

    paths.each do |path|
      get path

      assert_response :success, "#{path} should render anonymously"
      assert_no_match(/#{Regexp.escape(SECRET)}/, response.body,
        "#{path} leaked withheld content to an anonymous visitor")
    end
  end
end
```

- [ ] **Step 2: Run it**

Run: `bin/rails test test/controllers/anonymous_leak_sweep_test.rb`
Expected: PASS. **If it fails, the failing path has a real leak — fix the view, never the assertion.**

- [ ] **Step 3: Sweep the running app by hand**

The test covers rendered HTML. Confirm against the real server too, because a
leak can hide in a JSON endpoint or a cached fragment that the test does not exercise.

```bash
bin/rails runner 'SiteSetting.instance.update!(access_mode: "gated")'
bin/dev -b 0.0.0.0 -p 3005
```

Then, in a second shell:

```bash
for p in / /topics /meetings /committees; do
  printf "%-14s " "$p"
  curl -s "http://127.0.0.1:3005$p" | command grep -c "ZZQX_WITHHELD_CANARY_PHRASE"
done
```

Expected: `0` for every path.

Note: use `command grep`, not `grep` — a shell function shadows `grep` in this
environment and silently filters results.

- [ ] **Step 4: Run the full suite**

Run: `bin/rails test`
Expected: no new failures against the baseline

- [ ] **Step 5: Commit**

```bash
bin/rubocop
git add test/controllers/anonymous_leak_sweep_test.rb
git commit -m "test: add anonymous leak sweep across gated surfaces"
```

---

# Stage 5 — Always-Email Sign-In

Ends with every submitted address receiving a definitive answer by email while the
browser response stays identical.

### Task 15: Throttle model

**Files:**
- Create: `db/migrate/<timestamp>_create_sign_in_attempts.rb`
- Create: `app/models/sign_in_attempt.rb`
- Test: `test/models/sign_in_attempt_test.rb`

**Interfaces:**
- Consumes: nothing
- Produces: `SignInAttempt.throttled?(email) → Boolean`, `SignInAttempt.record!(email) → SignInAttempt`. Throttle window is 15 minutes.

Without this, anyone can type a stranger's address repeatedly and use the site's
domain to mail them.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/sign_in_attempt_test.rb
require "test_helper"

class SignInAttemptTest < ActiveSupport::TestCase
  test "a fresh address is not throttled" do
    assert_not SignInAttempt.throttled?("nobody@example.com")
  end

  test "an address is throttled after a recent attempt" do
    SignInAttempt.record!("someone@example.com")

    assert SignInAttempt.throttled?("someone@example.com")
  end

  test "the throttle expires after the window" do
    SignInAttempt.record!("someone@example.com")
    SignInAttempt.last.update!(created_at: 16.minutes.ago)

    assert_not SignInAttempt.throttled?("someone@example.com")
  end

  test "addresses are compared case-insensitively" do
    SignInAttempt.record!("Someone@Example.com")

    assert SignInAttempt.throttled?("someone@example.com")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/sign_in_attempt_test.rb`
Expected: FAIL with `NameError: uninitialized constant SignInAttempt`

- [ ] **Step 3: Write the migration**

```ruby
class CreateSignInAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :sign_in_attempts do |t|
      t.string :email_address, null: false
      t.timestamps
    end

    add_index :sign_in_attempts, [ :email_address, :created_at ]
  end
end
```

- [ ] **Step 4: Write the model**

```ruby
# app/models/sign_in_attempt.rb
class SignInAttempt < ApplicationRecord
  WINDOW = 15.minutes

  def self.throttled?(email_address)
    where(email_address: normalize(email_address))
      .where(created_at: WINDOW.ago..)
      .exists?
  end

  def self.record!(email_address)
    create!(email_address: normalize(email_address))
  end

  def self.normalize(email_address)
    email_address.to_s.strip.downcase
  end
end
```

- [ ] **Step 5: Migrate and run the tests**

Run: `bin/rails db:migrate && bin/rails test test/models/sign_in_attempt_test.rb`
Expected: PASS, 4 runs

- [ ] **Step 6: Commit**

```bash
bin/rubocop
git add db/migrate db/schema.rb app/models/sign_in_attempt.rb test/models/sign_in_attempt_test.rb
git commit -m "feat: add per-address sign-in attempt throttle"
```

---

### Task 16: Two new transactional messages

**Files:**
- Modify: `app/services/transactional_email.rb`
- Test: `test/services/transactional_email_test.rb`

**Interfaces:**
- Consumes: nothing
- Produces: `TransactionalEmail.no_account(email_address) → Message`, `TransactionalEmail.application_pending(user) → Message`. Both follow the existing `Message` struct contract and read their transactional ids from `LOOPS_NO_ACCOUNT_TRANSACTIONAL_ID` and `LOOPS_APPLICATION_PENDING_TRANSACTIONAL_ID`, raising `MissingTransactionalId` in production when absent.

- [ ] **Step 1: Write the failing test**

```ruby
# test/services/transactional_email_test.rb
require "test_helper"

class TransactionalEmailTest < ActiveSupport::TestCase
  test "no_account addresses the typed email and carries an apply url" do
    message = TransactionalEmail.no_account("stranger@example.com")

    assert_equal "stranger@example.com", message.email
    assert_equal "no_account", message.transactional_id
    assert_match(%r{/applications/new}, message.data_variables[:apply_url])
  end

  test "application_pending addresses the applicant" do
    user = User.create!(email_address: "waiting@example.com", status: "pending", disabled_at: Time.current)

    message = TransactionalEmail.application_pending(user)

    assert_equal "waiting@example.com", message.email
    assert_equal "application_pending", message.transactional_id
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/transactional_email_test.rb`
Expected: FAIL with `NoMethodError: undefined method 'no_account'`

- [ ] **Step 3: Add both message builders**

Append inside `class TransactionalEmail`, following the existing method style:

```ruby
  def self.no_account(email_address)
    Message.new(
      email: email_address,
      transactional_id: no_account_transactional_id,
      data_variables: {
        apply_url: Rails.application.routes.url_helpers.new_application_path
      }
    )
  end

  def self.application_pending(user)
    Message.new(
      email: user.email_address,
      transactional_id: application_pending_transactional_id,
      data_variables: {}
    )
  end

  def self.no_account_transactional_id
    ENV["LOOPS_NO_ACCOUNT_TRANSACTIONAL_ID"].presence || default_no_account_transactional_id
  end

  def self.application_pending_transactional_id
    ENV["LOOPS_APPLICATION_PENDING_TRANSACTIONAL_ID"].presence || default_application_pending_transactional_id
  end

  def self.default_no_account_transactional_id
    return "no_account" unless Rails.env.production?

    raise MissingTransactionalId, "LOOPS_NO_ACCOUNT_TRANSACTIONAL_ID is required in production"
  end

  def self.default_application_pending_transactional_id
    return "application_pending" unless Rails.env.production?

    raise MissingTransactionalId, "LOOPS_APPLICATION_PENDING_TRANSACTIONAL_ID is required in production"
  end
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/services/transactional_email_test.rb`
Expected: PASS, 2 runs

- [ ] **Step 5: Commit**

```bash
bin/rubocop
git add app/services/transactional_email.rb test/services/transactional_email_test.rb
git commit -m "feat: add no-account and application-pending transactional emails"
```

---

### Task 17: Always answer by email

**Files:**
- Modify: `app/controllers/sessions_controller.rb:11-22`
- Test: `test/controllers/sessions_always_email_test.rb`

**Interfaces:**
- Consumes: `SignInAttempt` (Task 15), `TransactionalEmail.no_account` / `.application_pending` (Task 16)
- Produces: no new interface

The browser response must stay byte-identical across all three branches. That
identity is the enumeration protection; the tests assert it directly.

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/sessions_always_email_test.rb
require "test_helper"

class SessionsAlwaysEmailTest < ActionDispatch::IntegrationTest
  test "an unknown address receives the no-account email" do
    sent = []
    stub_delivery(sent) do
      post public_session_path, params: { email_address: "stranger@example.com" }
    end

    assert_equal [ "no_account" ], sent.map(&:transactional_id)
    assert_redirected_to new_public_session_path
  end

  test "a pending applicant receives the pending email" do
    User.create!(email_address: "waiting@example.com", status: "pending", disabled_at: Time.current)

    sent = []
    stub_delivery(sent) do
      post public_session_path, params: { email_address: "waiting@example.com" }
    end

    assert_equal [ "application_pending" ], sent.map(&:transactional_id)
  end

  test "an active member receives a magic link" do
    User.create!(email_address: "member@example.com", status: "active")

    sent = []
    stub_delivery(sent) do
      post public_session_path, params: { email_address: "member@example.com" }
    end

    assert_equal 1, MagicLink.where(purpose: "sign_in").count
    assert_equal [ TransactionalEmail.magic_link_transactional_id ], sent.map(&:transactional_id)
  end

  test "all three branches produce an identical browser response" do
    User.create!(email_address: "member2@example.com", status: "active")
    User.create!(email_address: "waiting2@example.com", status: "pending", disabled_at: Time.current)

    bodies = [ "member2@example.com", "waiting2@example.com", "nobody2@example.com" ].map do |email|
      SignInAttempt.delete_all
      stub_delivery([]) { post public_session_path, params: { email_address: email } }
      follow_redirect!
      response.body
    end

    assert_equal 1, bodies.uniq.size, "responses must be indistinguishable across account states"
  end

  test "a throttled address sends no second email" do
    SignInAttempt.record!("stranger@example.com")

    sent = []
    stub_delivery(sent) do
      post public_session_path, params: { email_address: "stranger@example.com" }
    end

    assert_empty sent
    assert_redirected_to new_public_session_path
  end

  private

    def stub_delivery(collector)
      TransactionalEmail::Message.stub(:new, ->(**kwargs) {
        message = Struct.new(:email, :transactional_id, :data_variables, keyword_init: true).new(**kwargs)
        message.define_singleton_method(:deliver_now) { collector << self }
        message
      }) do
        yield
      end
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/sessions_always_email_test.rb`
Expected: FAIL — unknown addresses currently receive nothing

- [ ] **Step 3: Rewrite the create action**

Replace `SessionsController#create`:

```ruby
  def create
    email = params[:email_address].to_s.strip.downcase

    # Every branch below produces the same redirect. The identical response is
    # what prevents address enumeration; the email is what gives a real person
    # a definitive answer.
    deliver_sign_in_response(email) unless SignInAttempt.throttled?(email)

    redirect_to new_public_session_path, notice: "Check your email — we've sent you a message."
  rescue LoopsDelivery::DeliveryError
    redirect_to new_public_session_path, alert: "We couldn't send that message right now. Try again later."
  end
```

Add the private helper:

```ruby
    def deliver_sign_in_response(email)
      SignInAttempt.record!(email)
      user = User.find_by(email_address: email)

      if user&.active_for_authentication?
        link = MagicLink.create_for!(user, purpose: "sign_in")
        TransactionalEmail.magic_link(user, link).deliver_now
      elsif user&.status == "pending"
        TransactionalEmail.application_pending(user).deliver_now
      else
        TransactionalEmail.no_account(email).deliver_now
      end
    end
```

- [ ] **Step 4: Update the resend action to match the new copy**

```ruby
  def resend_expired_magic_link
    redirect_to new_public_session_path, notice: "Check your email — we've sent you a message."
  end
```

- [ ] **Step 5: Run the tests**

Run: `bin/rails test test/controllers/sessions_always_email_test.rb test/controllers/sessions_controller_test.rb`
Expected: PASS. Existing tests asserting the old string `"If that account can sign in, we sent a link."` will fail — update those assertions to the new copy. Do not weaken the identical-response test.

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: no new failures against the baseline

- [ ] **Step 7: Commit**

```bash
bin/rubocop
git add app/controllers/sessions_controller.rb test/controllers/sessions_always_email_test.rb test/controllers/sessions_controller_test.rb
git commit -m "feat: always answer sign-in attempts by email"
```

- [ ] **Step 8: Record the new Loops templates**

Two transactional templates must exist in Loops before this ships to production,
and their ids must be set as `LOOPS_NO_ACCOUNT_TRANSACTIONAL_ID` and
`LOOPS_APPLICATION_PENDING_TRANSACTIONAL_ID` in the Kamal env. Add both to the
deploy checklist in `.claude/skills/deploying/SKILL.md`, following the format
already used there for the existing Loops ids.

Content guidance for whoever writes the templates:

- **no_account** — "Someone asked for a sign-in link for this address. There's no account here. If that was you, here's how to request one: {{apply_url}}." No emoji.
- **application_pending** — "Your application is still under review. We'll email you as soon as it's decided." No emoji.

```bash
git add .claude/skills/deploying/SKILL.md
git commit -m "docs: note the two new Loops templates in the deploy checklist"
```

---

## Post-Implementation

- [ ] Update `docs/DEVELOPMENT_PLAN.md` with the access-mode model — it is the authoritative spec and this changes who can read the site.
- [ ] Update `CLAUDE.md` with a `Site access modes` note under Conventions, pointing at the design spec.
- [ ] Leave production in `open` mode until the teaser rendering has been checked against real content on the live server, then flip it from `/admin/site_settings`.
