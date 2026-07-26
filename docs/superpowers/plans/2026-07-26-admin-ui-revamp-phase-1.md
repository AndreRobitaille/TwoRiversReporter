# Admin UI Revamp — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `/admin` one authoritative navigation, a dense "Instrument" visual system in its own stylesheet, and restore the topic-triage workflow that a half-finished migration broke.

**Architecture:** A single frozen `Admin::Navigation` constant drives both the sidebar and the dashboard, so they cannot diverge. Admin styling moves out of the shared 6,720-line `application.css` into a new `admin.css` loaded only by the admin layout, containing a transitional utility layer plus twelve components at 13px density. The dead surfaces left over from the topics-admin rebuild are harvested for their lost functionality and then deleted.

**Tech Stack:** Rails 8.1, Propshaft, plain CSS (no Tailwind, no build step), Stimulus via importmap, Minitest integration tests.

**Spec:** `docs/superpowers/specs/2026-07-26-admin-ui-revamp-design.md`

## Global Constraints

- **No Tailwind, no CSS build step.** Propshaft serves plain `.css` files from `app/assets/stylesheets`. Never add a `package.json`, PostCSS, or a bundler.
- **All colours via CSS custom properties.** Never hardcode a hex value in `admin.css`. Use `--color-*`, `--space-*`, `--font-*` from `:root` and `.theme-silo` in `application.css`.
- **Typography roles are fixed:** Outfit (`--font-display`) for headings/nav/stats, always uppercase. Space Grotesk (`--font-body`) for paragraphs, buttons, forms. DM Mono (`--font-data`) for metadata, timestamps, IDs, status chips — always uppercase with wide tracking.
- **A page may not invent a class name.** If a view needs something the twelve components lack, grow the component and update the spec. This rule is what prevents the drift being fixed here.
- **Admin theme is `.theme-silo`.** Component overrides of shared names (`.card`, `.btn`, `.badge`, `.page-header`) are scoped `.theme-silo .card { … }` so the public site is untouched.
- **Utilities are unscoped and go last in `admin.css`**, at single-class specificity. A scoped component selector (`.theme-silo .card`, specificity 0-2-0) beats an unscoped utility (`.p-6`, 0-1-0). Where a utility must win over a component, write it as `.theme-silo .p-6` in the same block as the component it fights. Do not raise every utility's specificity preemptively.
- **Style is RuboCop Rails Omakase.** Run `bin/rubocop` before every commit.
- **Tests must be run and their real output reported.** Never claim a suite passes without having run it.
- **Do not touch public-site views or `application.css`'s public sections.** Removing admin-only rules from `application.css` is in scope; changing public rules is not.

---

## File Structure

**Created:**
- `app/models/admin/navigation.rb` — the single source of truth for admin nav structure. Plain value object, no AR. Sits beside the existing non-AR value objects (`network_prefix.rb`, `device_fingerprint.rb`, `known_context.rb`).
- `app/views/admin/shared/_sidebar.html.erb` — renders `Admin::Navigation`.
- `app/javascript/controllers/admin_sidebar_controller.js` — mobile drawer toggle.
- `app/assets/stylesheets/admin.css` — the entire admin visual system.
- `test/models/admin/navigation_test.rb`
- `test/controllers/admin/navigation_consistency_test.rb`
- `test/assets/admin_stylesheet_test.rb`
- `test/views/admin_view_hygiene_test.rb` — the two regression guards.

**Modified:**
- `app/views/layouts/admin.html.erb` — sidebar shell, stylesheet split, drawer controller.
- `app/views/admin/dashboard/show.html.erb` — rendered from `Admin::Navigation`.
- `app/views/admin/topics/_inbox_row.html.erb` — `dom_id` anchor, triage buttons, importance editor, preview expander.
- `app/controllers/admin/topics_controller.rb` — `render_turbo_update` targets `_inbox_row`.
- `app/services/admin/topics/inbox_query.rb` — extract `row_for(topic)`.
- `app/assets/stylesheets/application.css` — admin-only rules moved out.
- `app/views/admin/job_runs/index.html.erb`, `app/views/admin/jobs/show.html.erb` — renames, motif fix.
- `app/views/admin/prompt_templates/index.html.erb` — motif fix.
- ~30 admin views — inline styles replaced with utilities.

**Deleted:**
- `app/views/admin/topics/_topic.html.erb`, `_ai_decisions.html.erb`, `_history_snapshot.html.erb`, `_merge_candidates.html.erb`, `_merge_modal.html.erb`
- `app/views/admin/topic_repairs/show.html.erb`, `history.html.erb`, `_aliases.html.erb`, `_surgery.html.erb`, `_history.html.erb`, `_merge_candidates.html.erb`

---

## Task 1: `Admin::Navigation` constant

**Files:**
- Create: `app/models/admin/navigation.rb`
- Test: `test/models/admin/navigation_test.rb`

**Interfaces:**
- Produces: `Admin::Navigation::GROUPS` → `Array<Group>`. `Group = Data.define(:title, :items)`. `Item = Data.define(:label, :path_helper, :controller, :description)` where `path_helper` is a Symbol naming a route helper, `controller` is the `controller_name` string used for active-state matching, and `description` is the one-line dashboard subtitle. `Admin::Navigation.items` → flat `Array<Item>`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/admin/navigation_test.rb
require "test_helper"

module Admin
  class NavigationTest < ActiveSupport::TestCase
    test "exposes five groups in a fixed order" do
      assert_equal ["Topics", "Meetings", "The Record", "The Machine", "Site"],
                   Admin::Navigation::GROUPS.map(&:title)
    end

    test "every item's path helper resolves to a real route" do
      helpers = Rails.application.routes.url_helpers

      Admin::Navigation.items.each do |item|
        assert_respond_to helpers, item.path_helper,
          "#{item.label}: no route helper named #{item.path_helper}"
        path = helpers.public_send(item.path_helper)
        assert path.start_with?("/"), "#{item.label}: #{item.path_helper} did not return a path"
      end
    end

    test "every item's path is recognisable and routes to an admin controller" do
      helpers = Rails.application.routes.url_helpers

      Admin::Navigation.items.each do |item|
        path = helpers.public_send(item.path_helper)
        recognised = Rails.application.routes.recognize_path(path, method: :get)
        assert recognised[:controller].start_with?("admin/"),
          "#{item.label}: #{path} routes to #{recognised[:controller]}, not an admin controller"
      end
    end

    test "each item's controller matches the controller its path routes to" do
      helpers = Rails.application.routes.url_helpers

      Admin::Navigation.items.each do |item|
        path = helpers.public_send(item.path_helper)
        recognised = Rails.application.routes.recognize_path(path, method: :get)
        expected = recognised[:controller].split("/").last
        assert_equal expected, item.controller,
          "#{item.label}: declared controller #{item.controller.inspect} but path routes to #{expected.inspect}"
      end
    end

    test "every item has a non-blank description for the dashboard" do
      Admin::Navigation.items.each do |item|
        assert item.description.present?, "#{item.label} has no description"
      end
    end

    test "labels are unique" do
      labels = Admin::Navigation.items.map(&:label)
      assert_equal labels.uniq, labels
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/admin/navigation_test.rb`
Expected: FAIL — `NameError: uninitialized constant Admin::Navigation`

- [ ] **Step 3: Write the implementation**

```ruby
# app/models/admin/navigation.rb
module Admin
  # The single source of truth for admin navigation.
  #
  # Both the sidebar (app/views/admin/shared/_sidebar.html.erb) and the
  # dashboard launcher (app/views/admin/dashboard/show.html.erb) render from
  # this constant. They previously drifted into two different, disagreeing
  # lists; rendering both from one structure makes that impossible rather
  # than merely discouraged.
  #
  # Surfaces reached in context are deliberately absent: generated images
  # (from a topic or meeting), membership applications (from a user), and
  # personal security settings (the sidebar's user menu).
  class Navigation
    Item = Data.define(:label, :path_helper, :controller, :description)
    Group = Data.define(:title, :items)

    GROUPS = [
      Group.new(
        title: "Topics",
        items: [
          Item.new(label: "All Topics", path_helper: :admin_topics_path, controller: "topics",
                   description: "Review, triage, and combine civic topics."),
          Item.new(label: "Blocklist", path_helper: :admin_topic_blocklists_path, controller: "topic_blocklists",
                   description: "Names that may never become topics.")
        ]
      ),
      Group.new(
        title: "Meetings",
        items: [
          Item.new(label: "Meetings", path_helper: :admin_meetings_path, controller: "meetings",
                   description: "Find a meeting and manage its generated image."),
          Item.new(label: "Add Transcript", path_helper: :admin_transcript_imports_path, controller: "transcript_imports",
                   description: "Import YouTube captions or upload an SRT file."),
          Item.new(label: "Summaries", path_helper: :admin_summaries_path, controller: "summaries",
                   description: "Summary coverage and bulk regeneration.")
        ]
      ),
      Group.new(
        title: "The Record",
        items: [
          Item.new(label: "Committees", path_helper: :admin_committees_path, controller: "committees",
                   description: "Governing bodies and the descriptions the AI reads."),
          Item.new(label: "Members", path_helper: :admin_members_path, controller: "members",
                   description: "Officials, aliases, votes, and attendance."),
          Item.new(label: "Knowledge Sources", path_helper: :admin_knowledge_sources_path, controller: "knowledge_sources",
                   description: "Background context retrieved during summarization."),
          Item.new(label: "Knowledge Search", path_helper: :admin_search_path, controller: "searches",
                   description: "Query the knowledge base and meeting documents.")
        ]
      ),
      Group.new(
        title: "The Machine",
        items: [
          Item.new(label: "Run a Job", path_helper: :admin_job_runs_path, controller: "job_runs",
                   description: "Pick a job and targets, then enqueue."),
          Item.new(label: "Queue & Failures", path_helper: :admin_jobs_path, controller: "jobs",
                   description: "Worker status, pending work, and failed jobs."),
          Item.new(label: "Prompts", path_helper: :admin_prompt_templates_path, controller: "prompt_templates",
                   description: "The AI prompt text, with version history.")
        ]
      ),
      Group.new(
        title: "Site",
        items: [
          Item.new(label: "Access Mode", path_helper: :admin_site_settings_path, controller: "site_settings",
                   description: "Whether anonymous visitors see everything or a teaser."),
          Item.new(label: "Redirects", path_helper: :admin_redirects_path, controller: "redirects",
                   description: "Permanent redirects for moved URLs."),
          Item.new(label: "Admin Users", path_helper: :users_path, controller: "users",
                   description: "Accounts, applications, sessions, and passkeys."),
          Item.new(label: "Audit Log", path_helper: :admin_audit_events_path, controller: "audit_events",
                   description: "Destructive and privilege-changing actions.")
        ]
      )
    ].freeze

    def self.items
      GROUPS.flat_map(&:items)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/admin/navigation_test.rb`
Expected: 6 runs, 0 failures.

If test 4 fails, the declared `controller` does not match the route. Fix the constant, **not** the test — the test's whole purpose is catching that drift.

- [ ] **Step 5: Lint and commit**

```bash
bin/rubocop app/models/admin/navigation.rb test/models/admin/navigation_test.rb
git add app/models/admin/navigation.rb test/models/admin/navigation_test.rb
git commit -m "feat(admin): single source of truth for admin navigation"
```

---

## Task 2: Sidebar renders from `Admin::Navigation`

**Files:**
- Create: `app/views/admin/shared/_sidebar.html.erb`
- Modify: `app/views/layouts/admin.html.erb`
- Test: `test/controllers/admin/navigation_consistency_test.rb`

**Interfaces:**
- Consumes: `Admin::Navigation::GROUPS`, `Item#label`, `Item#path_helper`, `Item#controller` (Task 1).
- Produces: sidebar markup with `.adm-sidebar`, `.adm-sidebar__group`, `.adm-sidebar__link`, and `aria-current="page"` on the active link.

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/admin/navigation_consistency_test.rb
require "test_helper"

module Admin
  class NavigationConsistencyTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "nav-admin@example.com", admin: true)
      sign_in_as_admin(@admin)
    end

    test "sidebar links to every navigation item" do
      get admin_root_url
      assert_response :success

      Admin::Navigation.items.each do |item|
        path = Rails.application.routes.url_helpers.public_send(item.path_helper)
        assert_select "nav.adm-sidebar a[href=?]", path, text: item.label
      end
    end

    test "sidebar shows every group heading" do
      get admin_root_url

      Admin::Navigation::GROUPS.each do |group|
        assert_select "nav.adm-sidebar .adm-sidebar__group", text: group.title
      end
    end

    test "the current section's link is marked as the current page" do
      get admin_topics_url
      assert_response :success

      assert_select "nav.adm-sidebar a[aria-current=page]", count: 1, text: "All Topics"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/navigation_consistency_test.rb`
Expected: FAIL — no `nav.adm-sidebar` element exists.

- [ ] **Step 3: Create the sidebar partial**

```erb
<%# app/views/admin/shared/_sidebar.html.erb %>
<nav class="adm-sidebar" data-admin-sidebar-target="drawer" aria-label="Admin sections">
  <%= link_to admin_root_path, class: "adm-sidebar__brand" do %>
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path>
      <polyline points="9 22 9 12 15 12 15 22"></polyline>
    </svg>
    Admin
  <% end %>

  <% Admin::Navigation::GROUPS.each do |group| %>
    <div class="adm-sidebar__group"><%= group.title %></div>
    <% group.items.each do |item| %>
      <% current = controller_name == item.controller %>
      <%= link_to item.label,
            send(item.path_helper),
            class: "adm-sidebar__link#{' adm-sidebar__link--current' if current}",
            "aria-current": (current ? "page" : nil) %>
    <% end %>
  <% end %>

  <div class="adm-sidebar__foot">
    <%= link_to "Public Site", root_path, class: "adm-sidebar__link" %>
    <%= link_to "Security", settings_security_path, class: "adm-sidebar__link" %>
    <%= link_to "Sign Out", public_session_path, class: "adm-sidebar__link", data: { turbo_method: :delete } %>
  </div>
</nav>
```

- [ ] **Step 4: Replace the layout's header nav with the sidebar shell**

Replace lines 30–93 of `app/views/layouts/admin.html.erb` (everything from `<body …>` to `</body>`) with:

```erb
  <body class="theme-silo">
    <div class="adm-shell" data-controller="admin-sidebar">
      <button class="adm-drawer-toggle"
              type="button"
              aria-label="Toggle navigation"
              aria-expanded="false"
              data-admin-sidebar-target="toggle"
              data-action="click->admin-sidebar#toggle">
        <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <line x1="3" y1="12" x2="21" y2="12"></line>
          <line x1="3" y1="6" x2="21" y2="6"></line>
          <line x1="3" y1="18" x2="21" y2="18"></line>
        </svg>
      </button>

      <%= render "admin/shared/sidebar" %>

      <div class="adm-scrim" data-admin-sidebar-target="scrim" data-action="click->admin-sidebar#close" hidden></div>

      <main class="adm-main">
        <div class="adm-container">
          <%= yield %>
        </div>
      </main>
    </div>
  </body>
```

Note: the old footer is deliberately dropped. Its only unique links (Public Site, Sign Out) now live in `.adm-sidebar__foot`.

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/controllers/admin/navigation_consistency_test.rb`
Expected: 3 runs, 0 failures.

- [ ] **Step 6: Run the full admin suite for regressions**

Run: `bin/rails test test/controllers/admin`
Expected: all pass. Any failure asserting on the old header nav (`.site-nav`, `.site-header`) must be updated to the sidebar — those assertions are testing markup this task intentionally replaced.

- [ ] **Step 7: Lint and commit**

```bash
bin/rubocop
git add app/views/admin/shared/_sidebar.html.erb app/views/layouts/admin.html.erb test/controllers/admin/navigation_consistency_test.rb
git commit -m "feat(admin): render sidebar from Admin::Navigation"
```

---

## Task 3: Dashboard renders from the same constant

**Files:**
- Modify: `app/views/admin/dashboard/show.html.erb`
- Test: `test/controllers/admin/navigation_consistency_test.rb` (add to it)

**Interfaces:**
- Consumes: `Admin::Navigation::GROUPS`, `Item#description` (Task 1).

- [ ] **Step 1: Write the failing test**

Append inside `Admin::NavigationConsistencyTest` in `test/controllers/admin/navigation_consistency_test.rb`:

```ruby
    test "dashboard links to exactly the same items as the sidebar, and no others" do
      get admin_root_url
      assert_response :success

      expected = Admin::Navigation.items.map do |item|
        Rails.application.routes.url_helpers.public_send(item.path_helper)
      end.sort

      dashboard_links = css_select("main .adm-launcher a").map { |a| a["href"] }.sort

      assert_equal expected, dashboard_links,
        "dashboard and Admin::Navigation disagree — this is the exact drift the constant exists to prevent"
    end

    test "dashboard shows each item's description" do
      get admin_root_url

      Admin::Navigation.items.each do |item|
        assert_match item.description, response.body
      end
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/navigation_consistency_test.rb`
Expected: FAIL — no `.adm-launcher` elements; the two new tests fail while the earlier three still pass.

- [ ] **Step 3: Rewrite the dashboard**

Replace the whole of `app/views/admin/dashboard/show.html.erb`:

```erb
<% content_for(:title) { "Admin — Two Rivers Matters" } %>

<div class="adm-page-header">
  <div class="adm-page-header__eyebrow">Two Rivers Matters</div>
  <h1 class="adm-page-header__title">Admin</h1>
  <p class="adm-page-header__meta">Everything in the admin, grouped.</p>
</div>

<div class="adm-launcher">
  <% Admin::Navigation::GROUPS.each do |group| %>
    <section class="adm-launcher__group">
      <h2 class="adm-launcher__title"><%= group.title %></h2>
      <ul class="adm-launcher__list">
        <% group.items.each do |item| %>
          <li class="adm-launcher__item">
            <%= link_to item.label, send(item.path_helper), class: "adm-launcher__link" %>
            <span class="adm-launcher__desc"><%= item.description %></span>
          </li>
        <% end %>
      </ul>
    </section>
  <% end %>
</div>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/admin/navigation_consistency_test.rb`
Expected: 5 runs, 0 failures.

- [ ] **Step 5: Commit**

```bash
bin/rubocop
git add app/views/admin/dashboard/show.html.erb test/controllers/admin/navigation_consistency_test.rb
git commit -m "feat(admin): dashboard launcher renders from Admin::Navigation"
```

---

## Task 4: Mobile drawer as a Stimulus controller

**Files:**
- Create: `app/javascript/controllers/admin_sidebar_controller.js`
- Test: `test/controllers/admin/navigation_consistency_test.rb` (add to it)

**Interfaces:**
- Consumes: the `data-controller="admin-sidebar"` shell and the `drawer`, `toggle`, `scrim` targets emitted in Task 2.
- Produces: `.adm-shell--drawer-open` toggled on the shell element.

Stimulus controllers are eager-loaded from `app/javascript/controllers` via `eagerLoadControllersFrom` in `controllers/index.js` and `pin_all_from` in `config/importmap.rb`. A new file named `admin_sidebar_controller.js` registers itself as `admin-sidebar` with no further wiring.

- [ ] **Step 1: Write the failing test**

Append inside `Admin::NavigationConsistencyTest`:

```ruby
    test "the drawer is driven by Stimulus, not an inline handler" do
      get admin_root_url

      assert_select "[data-controller='admin-sidebar']", count: 1
      assert_select "[data-action='click->admin-sidebar#toggle']"
      assert_no_match(/onclick=/, response.body,
        "inline handlers break under CSP; use a Stimulus action")
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/navigation_consistency_test.rb -n /Stimulus/`
Expected: PASS on the `data-controller` assertions (Task 2 already emitted them) but the test is still worth keeping — if it passes immediately, temporarily reintroduce `onclick="1"` into the layout, confirm the test fails, then remove it. That proves the `assert_no_match` guard actually detects inline handlers rather than passing vacuously.

- [ ] **Step 3: Write the controller**

```javascript
// app/javascript/controllers/admin_sidebar_controller.js
import { Controller } from "@hotwired/stimulus"

// Off-canvas drawer for the admin sidebar below 900px. Above that breakpoint
// the sidebar is always visible and these methods are inert — CSS decides,
// not JS, so there is no resize listener to keep in sync.
export default class extends Controller {
  static targets = ["drawer", "toggle", "scrim"]
  static classes = ["open"]

  connect() {
    this.close()
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.element.classList.add("adm-shell--drawer-open")
    this.toggleTarget.setAttribute("aria-expanded", "true")
    if (this.hasScrimTarget) this.scrimTarget.removeAttribute("hidden")
  }

  close() {
    this.element.classList.remove("adm-shell--drawer-open")
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", "false")
    if (this.hasScrimTarget) this.scrimTarget.setAttribute("hidden", "hidden")
  }

  // Escape closes the drawer. Bound on the controller element via keydown in
  // the template is unnecessary — document-level is what users expect.
  handleKeydown(event) {
    if (event.key === "Escape") this.close()
  }

  get isOpen() {
    return this.element.classList.contains("adm-shell--drawer-open")
  }
}
```

- [ ] **Step 4: Bind Escape in the layout**

In `app/views/layouts/admin.html.erb`, extend the shell div's data attributes:

```erb
    <div class="adm-shell" data-controller="admin-sidebar" data-action="keydown@document->admin-sidebar#handleKeydown">
```

- [ ] **Step 5: Run the test**

Run: `bin/rails test test/controllers/admin/navigation_consistency_test.rb`
Expected: 6 runs, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/admin_sidebar_controller.js app/views/layouts/admin.html.erb test/controllers/admin/navigation_consistency_test.rb
git commit -m "feat(admin): stimulus-driven mobile sidebar drawer"
```

---

## Task 5: Split `admin.css` out of the shared stylesheet

**Files:**
- Create: `app/assets/stylesheets/admin.css`
- Modify: `app/views/layouts/admin.html.erb:24-25`
- Test: `test/controllers/admin/navigation_consistency_test.rb` (add to it)

**Interfaces:**
- Produces: `admin.css`, loaded after `application.css` by the admin layout only. Every later CSS task appends to this file.

The admin layout currently uses `stylesheet_link_tag :app`, which Propshaft expands to *every* file in `app/assets/stylesheets` — including `home.css` (724 lines) and `about.css` (391 lines) that admin never uses. Naming the two files it actually needs drops that.

- [ ] **Step 1: Write the failing test**

Append inside `Admin::NavigationConsistencyTest`:

```ruby
    test "admin loads its own stylesheet and not the public page stylesheets" do
      get admin_root_url

      assert_select "link[rel=stylesheet][href*='admin']", count: 1
      assert_select "link[rel=stylesheet][href*='application']", count: 1
      assert_select "link[rel=stylesheet][href*='home']", count: 0
      assert_select "link[rel=stylesheet][href*='about']", count: 0
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/navigation_consistency_test.rb -n /stylesheet/`
Expected: FAIL — `home` and `about` stylesheets are present because `:app` includes everything.

- [ ] **Step 3: Create the stylesheet skeleton**

```css
/* app/assets/stylesheets/admin.css
 *
 * The Silo admin visual system — "Instrument" density.
 *
 * Loaded ONLY by app/views/layouts/admin.html.erb, and always AFTER
 * application.css, from which it inherits every design token and the
 * .theme-silo palette. It defines no colours of its own.
 *
 * Order matters and is enforced by convention:
 *   1. Density base       — type scale and rhythm for a worked-in surface
 *   2. Shell & sidebar    — the admin chrome
 *   3. Components         — the twelve, and only the twelve
 *   4. Utilities          — transitional, unscoped, LAST so they win ties
 *
 * Rule: a page may not invent a class name. If a view needs something the
 * components lack, grow the component here and update
 * docs/superpowers/specs/2026-07-26-admin-ui-revamp-design.md.
 */

/* ============================================
   1. Density base
   ============================================ */

/* ============================================
   2. Shell & sidebar
   ============================================ */

/* ============================================
   3. Components
   ============================================ */

/* ============================================
   4. Utilities (transitional — removed in Phase 2)
   ============================================ */
```

- [ ] **Step 4: Point the layout at the two stylesheets it needs**

Replace lines 24–25 of `app/views/layouts/admin.html.erb`:

```erb
    <%# application.css supplies design tokens, reset, and the .theme-silo
        palette. admin.css layers the Instrument density and admin components
        on top and must load second. %>
    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
    <%= stylesheet_link_tag "admin", "data-turbo-track": "reload" %>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/controllers/admin/navigation_consistency_test.rb`
Expected: 7 runs, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/assets/stylesheets/admin.css app/views/layouts/admin.html.erb test/controllers/admin/navigation_consistency_test.rb
git commit -m "refactor(admin): split admin.css out of the shared stylesheet"
```

---

## Task 6: Define the 41 missing utilities

**Files:**
- Modify: `app/assets/stylesheets/admin.css` (section 4)
- Test: `test/assets/admin_stylesheet_test.rb`

**Interfaces:**
- Produces: 41 utility selectors. Task 8's hygiene guard depends on these existing.

These are the classes admin views already use that no stylesheet defines. Defining them stops 32 views from rendering broken. They are **transitional** — Phase 2 removes them as components take over.

- [ ] **Step 1: Write the failing test**

```ruby
# test/assets/admin_stylesheet_test.rb
require "test_helper"

class AdminStylesheetTest < ActiveSupport::TestCase
  STYLESHEET = Rails.root.join("app/assets/stylesheets/admin.css")

  UTILITIES = %w[
    m-0 mt-1 mt-3 mb-1 mb-3 mx-2 my-6 p-3 p-4 p-6
    gap-3 gap-6 space-y-2 space-y-3 space-y-6
    grid grid-cols-2 grow items-start justify-end align-middle
    w-8 whitespace-nowrap cursor-pointer
    text-left text-lg text-md font-semibold font-mono italic
    border-l border-t border-gray-200 border-yellow-200 border-danger-light
    bg-white bg-slate-50 bg-yellow-50
    text-yellow-600 text-yellow-700 text-yellow-800
  ].freeze

  def css
    @css ||= STYLESHEET.read
  end

  test "defines every transitional utility the admin views already use" do
    missing = UTILITIES.reject { |c| css.match?(/\.#{Regexp.escape(c)}(?![a-zA-Z0-9_-])/) }
    assert_empty missing, "admin.css does not define: #{missing.join(', ')}"
  end

  test "there are exactly 41 utilities, so the list cannot quietly grow" do
    assert_equal 41, UTILITIES.length
  end

  test "hardcodes no hex colours" do
    offenders = css.scan(/#[0-9a-fA-F]{3,8}\b/)
    assert_empty offenders,
      "admin.css must use design tokens, not literal colours: #{offenders.uniq.join(', ')}"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/assets/admin_stylesheet_test.rb`
Expected: FAIL — "admin.css does not define: m-0, mt-1, mt-3, …" listing all 41.

- [ ] **Step 3: Append the utility layer**

Add under section 4 of `app/assets/stylesheets/admin.css`:

```css
/* These exist because admin views were written with Tailwind idiom in a
 * project that has no Tailwind, leaving 32 views referencing classes nothing
 * defined. Rather than leave them broken while components are built, they are
 * defined here against real tokens. Phase 2 deletes this section as pages move
 * onto components. Do not add to it.
 *
 * Unscoped and last on purpose: a scoped component selector (.theme-silo .card,
 * 0-2-0) outranks an unscoped utility (.p-6, 0-1-0). Where a utility must beat a
 * component, write `.theme-silo .p-6` beside that component rather than raising
 * every utility here.
 */

/* --- spacing --- */
.m-0 { margin: 0; }
.mt-1 { margin-top: var(--space-1); }
.mt-3 { margin-top: var(--space-3); }
.mb-1 { margin-bottom: var(--space-1); }
.mb-3 { margin-bottom: var(--space-3); }
.mx-2 { margin-left: var(--space-2); margin-right: var(--space-2); }
.my-6 { margin-top: var(--space-6); margin-bottom: var(--space-6); }
.p-3 { padding: var(--space-3); }
.p-4 { padding: var(--space-4); }
.p-6 { padding: var(--space-6); }
.gap-3 { gap: var(--space-3); }
.gap-6 { gap: var(--space-6); }
.space-y-2 > * + * { margin-top: var(--space-2); }
.space-y-3 > * + * { margin-top: var(--space-3); }
.space-y-6 > * + * { margin-top: var(--space-6); }

/* --- layout --- */
.grid { display: grid; }
.grid-cols-2 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
.grow { flex-grow: 1; }
.items-start { align-items: flex-start; }
.justify-end { justify-content: flex-end; }
.align-middle { vertical-align: middle; }
.w-8 { width: 2rem; }
.whitespace-nowrap { white-space: nowrap; }
.cursor-pointer { cursor: pointer; }

/* --- type --- */
.text-left { text-align: left; }
.text-lg { font-size: var(--font-size-lg); }
.text-md { font-size: var(--font-size-base); }
.font-semibold { font-weight: var(--font-weight-semibold); }
.font-mono { font-family: var(--font-data); }
.italic { font-style: italic; }

/* --- borders and surfaces --- */
.border-l { border-left: 1px solid var(--color-border); }
.border-t { border-top: 1px solid var(--color-border); }
.border-gray-200 { border-color: var(--color-border); }
.border-yellow-200 { border-color: var(--color-warning); }
.border-danger-light { border-color: var(--color-danger-light); }
.bg-white { background-color: var(--color-surface); }
.bg-slate-50 { background-color: var(--color-bg); }
.bg-yellow-50 { background-color: var(--color-warning-light); }
.text-yellow-600,
.text-yellow-700,
.text-yellow-800 { color: var(--color-warning); }
```

`grid-cols-2` collapses to one column below 900px alongside the rest of the responsive rules added in Task 9. Do not add a media query here.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/assets/admin_stylesheet_test.rb`
Expected: 3 runs, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/assets/stylesheets/admin.css test/assets/admin_stylesheet_test.rb
git commit -m "fix(admin): define the 41 utility classes admin views referenced but nothing defined"
```

---

## Task 7: Resolve the 19 component and page classes

**Files:**
- Modify: `app/views/admin/job_runs/index.html.erb:4-13`
- Modify: `app/views/admin/prompt_templates/index.html.erb:4-13`
- Modify: `app/assets/stylesheets/admin.css` (section 3)
- Test: `test/assets/admin_stylesheet_test.rb` (add to it)

**Interfaces:**
- Produces: the motif and section-header mistakes removed from views; the remaining page containers defined.

Three of the 19 are mistakes and get **deleted from the views**, not defined:

| Wrong (undefined) | Right (already defined / exists) |
|---|---|
| `<svg class="atom-marker">` inlined | `render "shared/atom_marker", theme: "silo"` |
| `.section-header-label` | `.section-header__label` |
| `.section-header-line` | `.section-header__line` |

`users/show` and `site_settings/show` already do this correctly; `job_runs/index` and `prompt_templates/index` are the two that do not.

- [ ] **Step 1: Write the failing test**

Append to `AdminStylesheetTest`:

```ruby
  MISTAKES = {
    "atom-marker"          => 'render "shared/atom_marker", theme: "silo"',
    "section-header-label" => "section-header__label",
    "section-header-line"  => "section-header__line"
  }.freeze

  PAGE_CONTAINERS = %w[
    table table-responsive table-desc timestamp breadcrumb form-help
    flash-messages page-header-row badge--muted prose--sm
    topic-board-header transcript-imports-page transcript-imports-table-wrap
    transcript-imports-step-logs prompt-run-message generated-image-panel__block
  ].freeze

  test "the three motif and section-header mistakes are gone from every admin view" do
    views = Dir[Rails.root.join("app/views/admin/**/*.erb")]

    MISTAKES.each do |wrong, right|
      offenders = views.select do |path|
        File.read(path).match?(/\b#{Regexp.escape(wrong)}\b/)
      end
      assert_empty offenders.map { |p| p.sub("#{Rails.root}/", "") },
        "`#{wrong}` is undefined — use #{right} instead"
    end
  end

  test "defines every remaining page and component container" do
    missing = PAGE_CONTAINERS.reject { |c| css.match?(/\.#{Regexp.escape(c)}(?![a-zA-Z0-9_-])/) }
    assert_empty missing, "admin.css does not define: #{missing.join(', ')}"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/assets/admin_stylesheet_test.rb`
Expected: FAIL on both new tests — `atom-marker` found in two views; all 16 containers undefined.

- [ ] **Step 3: Fix the two views using the wrong motif**

In **both** `app/views/admin/job_runs/index.html.erb` and `app/views/admin/prompt_templates/index.html.erb`, replace the `<div class="page-header">` block (lines 3–15 and 3–15 respectively) with the correct pattern — the same one `users/show` uses:

For `job_runs/index.html.erb`:

```erb
<div class="adm-page-header">
  <div class="section-header">
    <%= render "shared/atom_marker", theme: "silo" %>
    <span class="section-header__label">Run a Job</span>
    <div class="section-header__line"></div>
  </div>
  <p class="adm-page-header__meta">Select a job type and targets, then enqueue.</p>
</div>
```

For `prompt_templates/index.html.erb`:

```erb
<div class="adm-page-header">
  <div class="section-header">
    <%= render "shared/atom_marker", theme: "silo" %>
    <span class="section-header__label">Prompt Templates</span>
    <div class="section-header__line"></div>
  </div>
  <p class="adm-page-header__meta">Edit the AI prompts that drive topic extraction, summarization, and analysis.</p>
</div>
```

- [ ] **Step 4: Define the remaining 16 containers**

Append under section 3 of `admin.css`:

```css
/* --- Page containers whose BEM children were styled but whose parents were not --- */
.theme-silo .topic-board-header { display: block; }
.theme-silo .transcript-imports-page { display: block; }
.theme-silo .transcript-imports-table-wrap { overflow-x: auto; }
.theme-silo .transcript-imports-step-logs {
  margin: var(--space-2) 0 0;
  padding-left: var(--space-4);
  font-size: var(--font-size-xs);
  color: var(--color-text-secondary);
}
.theme-silo .prompt-run-message {
  padding: var(--space-2) var(--space-3);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  background: var(--color-surface);
}
.theme-silo .generated-image-panel__block { margin-bottom: var(--space-3); }

/* --- Small shared primitives the older pages assumed existed --- */
.theme-silo .breadcrumb {
  margin-bottom: var(--space-3);
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--color-text-muted);
}
.theme-silo .page-header-row {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-4);
}
.theme-silo .form-help {
  margin: var(--space-1) 0 0;
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
}
.theme-silo .flash-messages { margin-bottom: var(--space-4); }
.theme-silo .timestamp {
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  letter-spacing: 0.06em;
  color: var(--color-text-secondary);
}
.theme-silo .table-desc {
  margin: var(--space-1) 0 0;
  font-size: var(--font-size-xs);
  color: var(--color-text-secondary);
}
.theme-silo .badge--muted {
  color: var(--color-text-muted);
  background: var(--color-surface-raised);
  border-color: var(--color-border);
}
.theme-silo .prose--sm { font-size: var(--font-size-sm); }
.theme-silo .table-responsive { overflow-x: auto; }
```

`.table` itself is defined by the data-table component in Task 10 — leave it out here.

- [ ] **Step 5: Run the test**

Run: `bin/rails test test/assets/admin_stylesheet_test.rb`
Expected: FAIL on `table` only, since Task 10 owns it. Temporarily remove `"table"` from `PAGE_CONTAINERS`, confirm all five tests pass, then restore it and leave that one failing until Task 10 — or reorder so Task 10 runs first. **Preferred:** move `"table"` out of `PAGE_CONTAINERS` now and assert it in Task 10 instead, so the suite is green at every commit.

- [ ] **Step 6: Verify the affected pages still render**

Run: `bin/rails test test/controllers/admin/job_runs_controller_test.rb test/controllers/admin/prompt_templates_controller_test.rb`
Expected: pass.

- [ ] **Step 7: Commit**

```bash
bin/rubocop
git add app/assets/stylesheets/admin.css app/views/admin/job_runs/index.html.erb app/views/admin/prompt_templates/index.html.erb test/assets/admin_stylesheet_test.rb
git commit -m "fix(admin): use the shared atom marker and defined section-header spellings"
```

---

## Task 8: Regression guard — no admin view may reference an undefined class

**Files:**
- Create: `test/views/admin_view_hygiene_test.rb`

**Interfaces:**
- Consumes: everything Tasks 6 and 7 defined.
- Produces: the guard that stops the whole class of bug from recurring.

This is the guard that would have caught the original problem. It must be proven to *detect*, not merely to pass — an absence assertion that passes for the wrong reason is worse than none.

- [ ] **Step 1: Write the guard**

```ruby
# test/views/admin_view_hygiene_test.rb
require "test_helper"

# Guards against the two failure modes found in the July 2026 admin audit:
# 32 of 60 views referencing class names no stylesheet defined, and ~50
# inline style attributes standing in for components that did not exist.
class AdminViewHygieneTest < ActiveSupport::TestCase
  STYLESHEETS = Rails.root.glob("app/assets/stylesheets/*.css")
  VIEWS = Rails.root.glob("app/views/admin/**/*.erb")

  # Class names built by ERB interpolation can't be checked statically.
  # Only literal, fully-formed class attributes are considered.
  LITERAL_CLASS_ATTR = /class="([^"<%]*)"/

  def defined_classes
    @defined_classes ||= STYLESHEETS.flat_map { |f| f.read.scan(/\.([a-zA-Z_][a-zA-Z0-9_-]*)/) }.flatten.to_set
  end

  def classes_used_in(path)
    path.read.scan(LITERAL_CLASS_ATTR).flatten
        .flat_map(&:split)
        .grep(/\A[a-zA-Z][a-zA-Z0-9_-]*\z/)
  end

  test "every class an admin view names is defined by some stylesheet" do
    undefined = Hash.new { |h, k| h[k] = [] }

    VIEWS.each do |path|
      (classes_used_in(path).uniq - defined_classes.to_a).each do |klass|
        undefined[klass] << path.relative_path_from(Rails.root).to_s
      end
    end

    assert_empty undefined,
      "these classes are used but defined nowhere:\n" +
      undefined.map { |k, v| "  .#{k} — #{v.join(', ')}" }.join("\n")
  end
end
```

- [ ] **Step 2: Prove the guard detects a real violation**

Temporarily add a bogus class to a view:

```bash
sed -i 's|<div class="adm-launcher">|<div class="adm-launcher totally-undefined-class">|' app/views/admin/dashboard/show.html.erb
bin/rails test test/views/admin_view_hygiene_test.rb
```

Expected: **FAIL** — `.totally-undefined-class — app/views/admin/dashboard/show.html.erb`.

If it passes, the guard is broken and must be fixed before continuing. Then revert:

```bash
git checkout app/views/admin/dashboard/show.html.erb
```

- [ ] **Step 3: Run the guard for real**

Run: `bin/rails test test/views/admin_view_hygiene_test.rb`
Expected: PASS. If anything is still listed, it is a genuine miss from Task 6 or 7 — define or remove it, do not weaken the guard.

- [ ] **Step 4: Commit**

```bash
git add test/views/admin_view_hygiene_test.rb
git commit -m "test(admin): guard against views referencing undefined classes"
```

---

## Task 9: Instrument density base, shell, and sidebar

**Files:**
- Modify: `app/assets/stylesheets/admin.css` (sections 1 and 2)
- Modify: `app/assets/stylesheets/application.css` — delete the admin-only blocks listed below
- Test: `test/assets/admin_stylesheet_test.rb` (add to it)

**Interfaces:**
- Consumes: `.adm-shell`, `.adm-sidebar*`, `.adm-main`, `.adm-container`, `.adm-drawer-toggle`, `.adm-scrim` (Task 2); `.adm-shell--drawer-open` (Task 4); `.adm-launcher*` (Task 3); `.adm-page-header*` (Tasks 3, 7).

- [ ] **Step 1: Write the failing test**

Append to `AdminStylesheetTest`:

```ruby
  SHELL = %w[
    adm-shell adm-sidebar adm-sidebar__brand adm-sidebar__group adm-sidebar__link
    adm-sidebar__link--current adm-sidebar__foot adm-main adm-container
    adm-drawer-toggle adm-scrim adm-launcher adm-launcher__group adm-launcher__title
    adm-launcher__list adm-launcher__item adm-launcher__link adm-launcher__desc
    adm-page-header adm-page-header__eyebrow adm-page-header__title adm-page-header__meta
  ].freeze

  test "defines the shell, sidebar, launcher, and page header" do
    missing = SHELL.reject { |c| css.match?(/\.#{Regexp.escape(c)}(?![a-zA-Z0-9_-])/) }
    assert_empty missing, "admin.css does not define: #{missing.join(', ')}"
  end

  test "collapses the sidebar to a drawer on small screens" do
    assert_match(/@media\s*\(max-width:\s*900px\)/, css)
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/assets/admin_stylesheet_test.rb`
Expected: FAIL listing all 22 shell classes.

- [ ] **Step 3: Write the density base (section 1)**

```css
/* Admin pages are worked in, not read. 13px base with tight rhythm fits
 * roughly twice the rows of the public site's 16px. Metadata is monospace so
 * IDs, timestamps and durations align into columns the eye can scan straight
 * down; colour is reserved for state, so a failure is findable without reading.
 */
.theme-silo {
  --adm-font-size: 0.8125rem;   /* 13px */
  --adm-font-size-sm: 0.75rem;  /* 12px */
  --adm-row-pad-y: var(--space-2);
  --adm-row-pad-x: var(--space-3);
  --adm-hairline: 1px solid var(--color-border);
  --adm-sidebar-width: 186px;
}

.theme-silo {
  font-size: var(--adm-font-size);
}

.theme-silo h1,
.theme-silo h2,
.theme-silo h3,
.theme-silo h4 {
  font-family: var(--font-display);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  margin: 0 0 var(--space-2);
}

.theme-silo h1 { font-size: 1.1875rem; font-weight: var(--font-weight-bold); }
.theme-silo h2 { font-size: 0.9375rem; font-weight: var(--font-weight-semibold); }
.theme-silo h3 { font-size: 0.8125rem; font-weight: var(--font-weight-semibold); }
.theme-silo h4 { font-size: 0.75rem; font-weight: var(--font-weight-semibold); }

.theme-silo p { margin: 0 0 var(--space-3); }
```

- [ ] **Step 4: Write the shell and sidebar (section 2)**

```css
.adm-shell {
  display: flex;
  min-height: 100vh;
  background: var(--color-bg);
}

/* --- Sidebar --- */
.adm-sidebar {
  flex: none;
  width: var(--adm-sidebar-width);
  padding: var(--space-3) 0 var(--space-6);
  background: var(--color-primary);
  color: var(--color-text-inverse);
  overflow-y: auto;
}

.adm-sidebar__brand {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: 0 var(--space-4) var(--space-3);
  font-family: var(--font-display);
  font-size: var(--font-size-xs);
  font-weight: var(--font-weight-bold);
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--color-text-inverse);
  text-decoration: none;
}
.adm-sidebar__brand:hover { color: var(--color-text-inverse); text-decoration: none; }

.adm-sidebar__group {
  padding: 0 var(--space-4);
  margin: var(--space-4) 0 var(--space-1);
  font-family: var(--font-data);
  font-size: 0.5625rem;
  letter-spacing: 0.13em;
  text-transform: uppercase;
  color: rgb(255 255 255 / 0.4);
}

.adm-sidebar__link {
  display: block;
  padding: var(--space-1) var(--space-4);
  font-family: var(--font-display);
  font-size: 0.71875rem;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: rgb(255 255 255 / 0.84);
  text-decoration: none;
}
.adm-sidebar__link:hover {
  background: rgb(255 255 255 / 0.08);
  color: var(--color-text-inverse);
  text-decoration: none;
}
.adm-sidebar__link--current {
  background: rgb(255 255 255 / 0.13);
  color: var(--color-text-inverse);
  box-shadow: inset 3px 0 0 var(--color-accent);
}

.adm-sidebar__foot {
  margin-top: var(--space-6);
  padding-top: var(--space-3);
  border-top: 1px solid rgb(255 255 255 / 0.15);
}

/* --- Main --- */
.adm-main { flex: 1; min-width: 0; }
.adm-container {
  max-width: 1200px;
  padding: var(--space-5) var(--space-6) var(--space-12);
}

/* --- Page header --- */
.adm-page-header { margin-bottom: var(--space-4); }
.adm-page-header__eyebrow {
  font-family: var(--font-data);
  font-size: 0.5625rem;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--color-text-muted);
  margin-bottom: var(--space-1);
}
.adm-page-header__title {
  font-family: var(--font-display);
  font-size: 1.1875rem;
  font-weight: var(--font-weight-bold);
  letter-spacing: 0.03em;
  text-transform: uppercase;
  margin: 0 0 var(--space-1);
}
.adm-page-header__meta {
  margin: 0 0 var(--space-3);
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  letter-spacing: 0.05em;
  color: var(--color-text-secondary);
}

/* --- Dashboard launcher --- */
.adm-launcher {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: var(--space-4);
}
.adm-launcher__group {
  padding: var(--space-4);
  border: var(--adm-hairline);
  border-radius: var(--radius-md);
  background: var(--color-surface);
}
.adm-launcher__title {
  margin: 0 0 var(--space-3);
  font-size: 0.6875rem;
  letter-spacing: 0.05em;
  color: var(--color-primary);
}
.adm-launcher__list { list-style: none; margin: 0; padding: 0; }
.adm-launcher__item { padding: var(--space-1) 0; }
.adm-launcher__item + .adm-launcher__item { border-top: 1px solid var(--color-surface-raised); }
.adm-launcher__link {
  display: block;
  font-weight: var(--font-weight-medium);
  color: var(--color-text);
  text-decoration: none;
}
.adm-launcher__link:hover { color: var(--color-accent); }
.adm-launcher__desc {
  display: block;
  font-size: var(--adm-font-size-sm);
  color: var(--color-text-muted);
}

/* --- Drawer chrome: hidden above the breakpoint --- */
.adm-drawer-toggle { display: none; }
.adm-scrim { display: none; }

@media (max-width: 900px) {
  .adm-sidebar {
    position: fixed;
    inset: 0 auto 0 0;
    z-index: 40;
    transform: translateX(-100%);
    transition: transform var(--transition-normal);
  }
  .adm-shell--drawer-open .adm-sidebar { transform: translateX(0); }

  .adm-drawer-toggle {
    display: inline-flex;
    position: fixed;
    top: var(--space-2);
    left: var(--space-2);
    z-index: 50;
    padding: var(--space-2);
    border: var(--adm-hairline);
    border-radius: var(--radius-sm);
    background: var(--color-surface);
    color: var(--color-text);
  }

  .adm-shell--drawer-open .adm-scrim {
    display: block;
    position: fixed;
    inset: 0;
    z-index: 30;
    background: rgb(0 0 0 / 0.4);
  }

  .adm-container { padding: var(--space-12) var(--space-4) var(--space-8); }

  .grid-cols-2 { grid-template-columns: 1fr; }
}
```

- [ ] **Step 5: Remove the admin-only blocks now superseded in `application.css`**

Delete these blocks from `app/assets/stylesheets/application.css` (they styled the old top-nav admin chrome, which no longer exists):

- the `.admin-two-column`, `.admin-two-column__main`, `.admin-two-column__aside`, `.admin-sidebar` block beginning at the `/* ... */` marker near line 1856, through the `.admin-sidebar h2` rule
- the `.admin-topics-filters*` and `.admin-topics-table*` blocks (roughly lines 1992–2110)
- the responsive `@media` overrides for `.admin-topics-filters`, `.admin-two-column`, `.admin-sidebar` (roughly lines 2112–2135)

Move each into `admin.css` section 3 **verbatim first**, then restyle in Tasks 10–11. Moving and restyling in one step makes a regression impossible to bisect.

- [ ] **Step 6: Run the tests**

Run: `bin/rails test test/assets/admin_stylesheet_test.rb test/views/admin_view_hygiene_test.rb test/controllers/admin`
Expected: all pass. The hygiene guard is the one that catches a class accidentally dropped during the move.

- [ ] **Step 7: Check it in a browser**

Start the server and look at `/admin`, `/admin/topics`, and `/admin/job_runs` at both desktop width and ~400px:

```bash
bin/dev
```

Confirm: sidebar visible and grouped at desktop; hamburger + drawer + scrim at 400px; Escape closes the drawer; the current section's link shows the terra-cotta left edge.

- [ ] **Step 8: Commit**

```bash
bin/rubocop
git add app/assets/stylesheets/admin.css app/assets/stylesheets/application.css test/assets/admin_stylesheet_test.rb
git commit -m "feat(admin): instrument density, sidebar shell, and dashboard launcher styling"
```

---

## Task 10: Data table, status chips, pagination, empty state

**Files:**
- Modify: `app/assets/stylesheets/admin.css` (section 3)
- Test: `test/assets/admin_stylesheet_test.rb` (add to it)

**Interfaces:**
- Produces: `.adm-table`, `.adm-table__row--{ok,warn,danger}`, `.adm-chip`, `.adm-chip--{ok,warn,danger,info,neutral}`, `.adm-pagination`, `.adm-empty`, plus a bare `table` default so the ten views using unclassed `<table>` inherit the component.

- [ ] **Step 1: Write the failing test**

Append to `AdminStylesheetTest`:

```ruby
  DATA_COMPONENTS = %w[
    adm-table adm-table__sort adm-table__row--ok adm-table__row--warn adm-table__row--danger
    adm-chip adm-chip--ok adm-chip--warn adm-chip--danger adm-chip--info adm-chip--neutral
    adm-pagination adm-empty table
  ].freeze

  test "defines the data table, chips, pagination, and empty state" do
    missing = DATA_COMPONENTS.reject { |c| css.match?(/\.#{Regexp.escape(c)}(?![a-zA-Z0-9_-])/) }
    assert_empty missing, "admin.css does not define: #{missing.join(', ')}"
  end

  test "table metadata cells use the data typeface" do
    assert_match(/--font-data/, css)
  end
```

Also delete `"table"` from `PAGE_CONTAINERS` in Task 7's test if it is still there — it is asserted here now.

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/assets/admin_stylesheet_test.rb`
Expected: FAIL listing the 14 classes.

- [ ] **Step 3: Write the components**

```css
/* --- Data table --------------------------------------------------------
 * Ten admin views use a bare, unclassed <table>. Styling the element itself
 * inside .theme-silo means they all inherit the component with no edits;
 * .adm-table is the explicit opt-in for new markup. Row state rides a 3px
 * left edge so a failed or flagged row is findable without reading it.
 */
.theme-silo table,
.theme-silo .adm-table {
  width: 100%;
  border-collapse: collapse;
  background: var(--color-surface);
  font-size: var(--adm-font-size);
}

.theme-silo table thead th,
.theme-silo .adm-table thead th {
  padding: var(--space-2) var(--adm-row-pad-x);
  border-top: var(--adm-hairline);
  border-bottom: var(--adm-hairline);
  background: var(--color-bg);
  font-family: var(--font-data);
  font-size: 0.5625rem;
  font-weight: var(--font-weight-normal);
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--color-text-muted);
  text-align: left;
}

.theme-silo table tbody td,
.theme-silo .adm-table tbody td {
  padding: var(--adm-row-pad-y) var(--adm-row-pad-x);
  border-bottom: 1px solid var(--color-surface-raised);
  vertical-align: middle;
}

.theme-silo table tbody tr:hover td,
.theme-silo .adm-table tbody tr:hover td {
  background: var(--color-surface-hover);
}

/* IDs, timestamps, counts — monospace so columns align for straight-down
 * scanning. This is the whole reason the density choice works. */
.theme-silo .data-cell,
.theme-silo td.text-right {
  font-family: var(--font-data);
  font-size: var(--adm-font-size-sm);
  color: var(--color-text-secondary);
}

.theme-silo .adm-table__sort {
  color: var(--color-text-muted);
  text-decoration: none;
}
.theme-silo .adm-table__sort:hover { color: var(--color-accent); }

.theme-silo .adm-table__row--ok     { box-shadow: inset 3px 0 0 var(--color-success); }
.theme-silo .adm-table__row--warn   { box-shadow: inset 3px 0 0 var(--color-warning); }
.theme-silo .adm-table__row--danger { box-shadow: inset 3px 0 0 var(--color-danger); }

/* --- Status chips --- */
.theme-silo .adm-chip {
  display: inline-block;
  padding: 1px var(--space-2);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  background: var(--color-surface);
  font-family: var(--font-data);
  font-size: 0.5625rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--color-text-secondary);
  white-space: nowrap;
}
.theme-silo .adm-chip--ok      { color: var(--color-success); background: var(--color-success-light); border-color: var(--color-success); }
.theme-silo .adm-chip--warn    { color: var(--color-warning); background: var(--color-warning-light); border-color: var(--color-warning); }
.theme-silo .adm-chip--danger  { color: var(--color-danger);  background: var(--color-danger-light);  border-color: var(--color-danger); }
.theme-silo .adm-chip--info    { color: var(--color-ai-text); background: var(--color-ai-bg);         border-color: var(--color-ai-border); }
.theme-silo .adm-chip--neutral { color: var(--color-text-muted); background: var(--color-surface-raised); }

/* --- Pagination --- */
.theme-silo .adm-pagination {
  display: flex;
  gap: var(--space-2);
  align-items: center;
  margin-top: var(--space-4);
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  letter-spacing: 0.06em;
  text-transform: uppercase;
}

/* --- Empty state --- */
.theme-silo .adm-empty,
.theme-silo .empty-state {
  padding: var(--space-6);
  border: 1px dashed var(--color-border);
  border-radius: var(--radius-md);
  text-align: center;
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--color-text-muted);
}
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/assets/admin_stylesheet_test.rb test/views/admin_view_hygiene_test.rb`
Expected: pass.

- [ ] **Step 5: Check a table-heavy page in the browser**

With `bin/dev` running, open `/admin/job_runs`, `/admin/committees`, and `/admin/audit_events`. Confirm rows are dense, headers are small-caps monospace, and hover highlights the row.

- [ ] **Step 6: Commit**

```bash
git add app/assets/stylesheets/admin.css test/assets/admin_stylesheet_test.rb
git commit -m "feat(admin): instrument data table, status chips, pagination, empty state"
```

---

## Task 11: Forms, buttons, panels, detail layout, flash, modal, toolbar

**Files:**
- Modify: `app/assets/stylesheets/admin.css` (section 3)
- Test: `test/assets/admin_stylesheet_test.rb` (add to it)

**Interfaces:**
- Produces: `.adm-toolbar`, `.adm-seg`, `.adm-seg__option`, `.adm-seg__option--on`, `.adm-panel`, `.adm-panel__label`, `.adm-detail`, `.adm-detail__main`, `.adm-detail__rail`, plus scoped overrides for the shared `.card`, `.btn`, `.badge`, `.form-input`, `.form-label`, `.flash`, `.modal` at Instrument density.

- [ ] **Step 1: Write the failing test**

Append to `AdminStylesheetTest`:

```ruby
  CHROME_COMPONENTS = %w[
    adm-toolbar adm-seg adm-seg__option adm-seg__option--on
    adm-panel adm-panel__label adm-detail adm-detail__main adm-detail__rail
  ].freeze

  test "defines the toolbar, segmented control, panel, and detail layout" do
    missing = CHROME_COMPONENTS.reject { |c| css.match?(/\.#{Regexp.escape(c)}(?![a-zA-Z0-9_-])/) }
    assert_empty missing, "admin.css does not define: #{missing.join(', ')}"
  end

  test "shared component names are overridden scoped to the admin theme only" do
    %w[card btn badge form-input flash modal].each do |shared|
      assert_match(/\.theme-silo\s+\.#{Regexp.escape(shared)}(?![a-zA-Z0-9_-])/, css,
        ".#{shared} must be overridden as `.theme-silo .#{shared}` so the public site is untouched")
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/assets/admin_stylesheet_test.rb`
Expected: FAIL on both.

- [ ] **Step 3: Write the components**

```css
/* --- Toolbar and segmented control --- */
.theme-silo .adm-toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
  align-items: center;
  margin-bottom: var(--space-3);
}

.theme-silo .adm-seg {
  display: inline-flex;
  border: var(--adm-hairline);
  border-radius: var(--radius-sm);
  overflow: hidden;
  background: var(--color-surface);
}
.theme-silo .adm-seg__option {
  padding: var(--space-1) var(--space-3);
  border: 0;
  border-right: var(--adm-hairline);
  background: transparent;
  font-family: var(--font-data);
  font-size: 0.59375rem;
  letter-spacing: 0.07em;
  text-transform: uppercase;
  color: var(--color-text-secondary);
  text-decoration: none;
  cursor: pointer;
}
.theme-silo .adm-seg__option:last-child { border-right: 0; }
.theme-silo .adm-seg__option:hover { background: var(--color-surface-hover); text-decoration: none; }
.theme-silo .adm-seg__option--on {
  background: var(--color-primary);
  color: var(--color-text-inverse);
}

/* --- Panel --- */
.theme-silo .adm-panel,
.theme-silo .card {
  padding: var(--space-4);
  border: var(--adm-hairline);
  border-radius: var(--radius-md);
  background: var(--color-surface);
}
.theme-silo .adm-panel__label,
.theme-silo .topic-panel-label {
  margin-bottom: var(--space-2);
  font-family: var(--font-data);
  font-size: 0.5625rem;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--color-text-muted);
}

/* --- Detail layout: main column plus a rail --- */
.theme-silo .adm-detail,
.theme-silo .admin-two-column,
.theme-silo .topic-detail-layout {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 300px;
  gap: var(--space-5);
  align-items: start;
}
.theme-silo .adm-detail__main,
.theme-silo .adm-detail__rail { min-width: 0; }

@media (max-width: 900px) {
  .theme-silo .adm-detail,
  .theme-silo .admin-two-column,
  .theme-silo .topic-detail-layout { grid-template-columns: 1fr; }
}

/* --- Buttons --- */
.theme-silo .btn {
  display: inline-flex;
  align-items: center;
  gap: var(--space-1);
  padding: var(--space-1) var(--space-3);
  border: var(--adm-hairline);
  border-radius: var(--radius-sm);
  background: var(--color-surface);
  font-family: var(--font-display);
  font-size: 0.625rem;
  font-weight: var(--font-weight-medium);
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--color-text);
  text-decoration: none;
  cursor: pointer;
}
.theme-silo .btn:hover { background: var(--color-surface-hover); text-decoration: none; }
.theme-silo .btn--primary   { background: var(--color-primary); border-color: var(--color-primary); color: var(--color-text-inverse); }
.theme-silo .btn--primary:hover { background: var(--color-primary-hover); }
.theme-silo .btn--danger    { background: var(--color-danger); border-color: var(--color-danger); color: var(--color-text-inverse); }
.theme-silo .btn--success   { background: var(--color-success); border-color: var(--color-success); color: var(--color-text-inverse); }
.theme-silo .btn--ghost     { background: transparent; border-color: transparent; color: var(--color-text-secondary); }
.theme-silo .btn--ghost:hover { border-color: var(--color-border); }
.theme-silo .btn--sm        { padding: 1px var(--space-2); font-size: 0.5625rem; }
.theme-silo .btn[disabled]  { opacity: 0.45; cursor: not-allowed; }

/* --- Badges: keep the shared name, adopt chip proportions --- */
.theme-silo .badge {
  display: inline-block;
  padding: 1px var(--space-2);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  font-family: var(--font-data);
  font-size: 0.5625rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  white-space: nowrap;
}

/* --- Forms --- */
.theme-silo .form-label,
.theme-silo label {
  display: block;
  margin-bottom: var(--space-1);
  font-family: var(--font-data);
  font-size: 0.5625rem;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--color-text-secondary);
}
.theme-silo .form-input,
.theme-silo .form-select,
.theme-silo .form-textarea,
.theme-silo input[type="text"],
.theme-silo input[type="search"],
.theme-silo input[type="url"],
.theme-silo input[type="date"],
.theme-silo input[type="number"],
.theme-silo select,
.theme-silo textarea {
  padding: var(--space-1) var(--space-2);
  border: var(--adm-hairline);
  border-radius: var(--radius-sm);
  background: var(--color-surface);
  font-family: var(--font-body);
  font-size: var(--adm-font-size);
  color: var(--color-text);
}
.theme-silo .form-textarea--code {
  font-family: var(--font-data);
  font-size: var(--adm-font-size-sm);
  line-height: var(--line-height-normal);
}
.theme-silo .form-group { margin-bottom: var(--space-3); }
.theme-silo .form-hint {
  margin: var(--space-1) 0 0;
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
}

/* --- Flash --- */
.theme-silo .flash {
  padding: var(--space-2) var(--space-3);
  margin-bottom: var(--space-3);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  font-size: var(--adm-font-size);
}
.theme-silo .flash--success { border-color: var(--color-success); background: var(--color-success-light); }
.theme-silo .flash--danger  { border-color: var(--color-danger);  background: var(--color-danger-light); }

/* --- Modal --- */
.theme-silo .modal__panel {
  padding: var(--space-5);
  border: var(--adm-hairline);
  border-radius: var(--radius-md);
  background: var(--color-surface);
  box-shadow: var(--shadow-lg);
}
```

- [ ] **Step 4: Run the full suite**

Run: `bin/rails test`
Expected: all pass. This is the first task that restyles shared component names, so a public-site regression would surface here. If a *public* test fails, a selector is missing its `.theme-silo` scope — fix the CSS, not the test.

- [ ] **Step 5: Browser check**

With `bin/dev` running, walk `/admin/topics`, `/admin/topics/:id`, `/admin/transcript_imports`, `/admin/prompt_templates/:id/edit`, `/admin/users`. Confirm nothing is unstyled and the public homepage at `/` is visually unchanged.

- [ ] **Step 6: Commit**

```bash
git add app/assets/stylesheets/admin.css test/assets/admin_stylesheet_test.rb
git commit -m "feat(admin): instrument forms, buttons, panels, detail layout, flash, modal"
```

---

## Task 12: Restore topic triage on the inbox

**Files:**
- Modify: `app/services/admin/topics/inbox_query.rb`
- Modify: `app/views/admin/topics/_inbox_row.html.erb`
- Modify: `app/controllers/admin/topics_controller.rb:52-62, 172-183`
- Test: `test/controllers/admin/topics_review_test.rb`

**Interfaces:**
- Consumes: `Admin::Topics::InboxQuery::Row` (existing) — `topic_id`, `name`, `status`, `review_status`, `pinned`, `alias_names`, `signals`, `mention_count`, `last_seen_at`, `last_activity_at`.
- Produces: `Admin::Topics::InboxQuery.row_for(topic)` → `Row`. `_inbox_row` becomes a `<tbody id="topic_<id>">` so `turbo_stream.replace` has a real target.

**This is the task that fixes the broken workflow.** `approve`, `block`, `unblock`, `needs_review`, `pin`, and `unpin` all have routes and controller actions, but every reference to them lives in `_topic.html.erb` and `_ai_decisions.html.erb`, neither of which is rendered. `render_turbo_update` compounds it by replacing `dom_id(@topic)` — an id `_inbox_row` never emits.

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/admin/topics_review_test.rb — replace the file
require "test_helper"
require "securerandom"

module Admin
  class TopicsReviewTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "triage@example.com", admin: true)
      sign_in_as_admin(@admin)
    end

    def proposed_topic
      Topic.create!(name: "proposed #{SecureRandom.hex(4)}",
                    status: "proposed", review_status: "proposed", lifecycle_status: "active")
    end

    test "each inbox row carries a dom id turbo can replace" do
      topic = proposed_topic
      get admin_topics_url

      assert_select "tbody#topic_#{topic.id}", count: 1
    end

    test "a proposed topic offers approve and block from the index" do
      topic = proposed_topic
      get admin_topics_url

      assert_select "form[action=?]", approve_admin_topic_path(topic)
      assert_select "form[action=?]", block_admin_topic_path(topic)
    end

    test "an approved topic offers needs-review and block" do
      topic = Topic.create!(name: "approved #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      get admin_topics_url

      assert_select "form[action=?]", needs_review_admin_topic_path(topic)
      assert_select "form[action=?]", block_admin_topic_path(topic)
    end

    test "a blocked topic offers unblock" do
      topic = Topic.create!(name: "blocked #{SecureRandom.hex(4)}", status: "blocked", review_status: "blocked")
      get admin_topics_url

      assert_select "form[action=?]", unblock_admin_topic_path(topic)
    end

    test "every row offers pin or unpin" do
      pinned = Topic.create!(name: "pinned #{SecureRandom.hex(4)}", status: "approved", review_status: "approved", pinned: true)
      unpinned = Topic.create!(name: "unpinned #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      get admin_topics_url

      assert_select "form[action=?]", unpin_admin_topic_path(pinned)
      assert_select "form[action=?]", pin_admin_topic_path(unpinned)
    end

    test "approving actually approves and returns a replaceable row" do
      topic = proposed_topic

      post approve_admin_topic_path(topic), as: :turbo_stream

      assert_response :success
      assert_equal "approved", topic.reload.status
      assert_equal "approved", topic.review_status
      assert_match "turbo-stream", response.media_type
      assert_match "topic_#{topic.id}", response.body,
        "the turbo stream must target the id the index actually rendered"
    end

    test "blocking blocks the topic" do
      topic = proposed_topic
      post block_admin_topic_path(topic), as: :turbo_stream
      assert_equal "blocked", topic.reload.status
    end

    test "pinning pins the topic" do
      topic = Topic.create!(name: "topin #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      post pin_admin_topic_path(topic), as: :turbo_stream
      assert topic.reload.pinned?
    end

    test "row_for builds a row from a topic" do
      topic = proposed_topic
      row = Admin::Topics::InboxQuery.row_for(topic)

      assert_equal topic.id, row.topic_id
      assert_equal topic.name, row.name
      assert_equal "proposed", row.review_status
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/topics_review_test.rb`
Expected: FAIL — no `tbody#topic_N`, no triage forms, `NoMethodError: undefined method 'row_for'`.

- [ ] **Step 3: Extract `row_for` in `InboxQuery`**

In `app/services/admin/topics/inbox_query.rb`, add a class method and make `call` use it. Replace the `call` method and add above `private`:

```ruby
      # Building a Row from a Topic is needed in two places: the index query,
      # and the controller's turbo_stream response after a triage action.
      # Keeping one implementation means a replaced row can never disagree
      # with the row the index originally rendered.
      def self.row_for(topic)
        Row.new(
          topic_id: topic.id,
          name: topic.name,
          description: topic.description,
          status: topic.status,
          review_status: topic.review_status,
          lifecycle_status: topic.lifecycle_status,
          pinned: topic.pinned?,
          alias_count: topic.topic_aliases.size,
          alias_names: topic.topic_aliases.map(&:name).sort,
          mention_count: topic.agenda_items.size,
          reason_label: new.send(:reason_for, topic),
          signals: new.send(:signals_for, topic),
          updated_at: topic.updated_at,
          created_at: topic.created_at,
          last_seen_at: topic.last_seen_at,
          last_activity_at: topic.last_activity_at
        )
      end

      def call
        sort_rows(flagged_scope.map { |topic| self.class.row_for(topic) })
      end
```

`reason_for` and `signals_for` are instance methods that use no instance state, so `new.send(...)` is safe. Leave them private.

- [ ] **Step 4: Rewrite `_inbox_row` as a `tbody` with triage actions**

Replace `app/views/admin/topics/_inbox_row.html.erb` entirely:

```erb
<%# A tbody, not a tr, so turbo_stream.replace has a stable element to swap
    and so a future preview row can live inside the same block. The id must
    match helpers.dom_id(topic) — "topic_<id>" — which is what
    Admin::TopicsController#render_turbo_update targets. %>
<% row_state = if row.review_status == "proposed"
                 "adm-table__row--warn"
               elsif row.status == "blocked"
                 "adm-table__row--danger"
               else
                 "adm-table__row--ok"
               end %>
<tbody id="topic_<%= row.topic_id %>">
  <tr class="<%= row_state %>">
    <td>
      <div class="font-semibold">
        <%= link_to row.name, admin_topic_path(row.topic_id), data: { turbo_frame: "_top" } %>
      </div>
      <% if row.alias_names.any? %>
        <div class="table-desc"><%= row.alias_names.join(", ") %></div>
      <% end %>
    </td>
    <td>
      <% review_chip = case row.review_status
         when "proposed" then "adm-chip--warn"
         when "blocked" then "adm-chip--danger"
         else "adm-chip--ok"
      end %>
      <span class="adm-chip <%= review_chip %>"><%= row.review_status %></span>
      <% if row.status != row.review_status %>
        <span class="adm-chip adm-chip--neutral"><%= row.status %></span>
      <% end %>
    </td>
    <td>
      <% row.signals.each do |signal| %>
        <span class="adm-chip adm-chip--neutral"><%= signal %></span>
      <% end %>
    </td>
    <td class="text-right"><%= row.mention_count %></td>
    <td class="data-cell"><%= row.last_seen_at&.to_date || "—" %></td>
    <td class="data-cell"><%= row.last_activity_at&.to_date || "—" %></td>
    <td class="text-right">
      <div class="flex gap-2 justify-end">
        <% if row.review_status == "proposed" %>
          <%= button_to "Approve", approve_admin_topic_path(row.topic_id), method: :post, class: "btn btn--success btn--sm" %>
          <%= button_to "Block", block_admin_topic_path(row.topic_id), method: :post, class: "btn btn--danger btn--sm" %>
        <% elsif row.review_status == "blocked" || row.status == "blocked" %>
          <%= button_to "Unblock", unblock_admin_topic_path(row.topic_id), method: :post, class: "btn btn--sm" %>
        <% else %>
          <%= button_to "Needs review", needs_review_admin_topic_path(row.topic_id), method: :post, class: "btn btn--sm" %>
          <%= button_to "Block", block_admin_topic_path(row.topic_id), method: :post, class: "btn btn--danger btn--sm" %>
        <% end %>

        <% if row.pinned %>
          <%= button_to "Unpin", unpin_admin_topic_path(row.topic_id), method: :post, class: "btn btn--primary btn--sm" %>
        <% else %>
          <%= button_to "Pin", pin_admin_topic_path(row.topic_id), method: :post, class: "btn btn--sm" %>
        <% end %>

        <%= link_to "Open", admin_topic_path(row.topic_id), class: "btn btn--sm" %>
      </div>
    </td>
  </tr>
</tbody>
```

- [ ] **Step 5: Stop `index.html.erb` wrapping the loop in its own `<tbody>`**

The partial now supplies its own `<tbody>`, so the wrapper in `app/views/admin/topics/index.html.erb` (lines 44–48) would nest one inside another. Replace:

```erb
      <tbody>
        <% @inbox_rows.each do |row| %>
          <%= render "inbox_row", row: row %>
        <% end %>
      </tbody>
```

with:

```erb
      <% @inbox_rows.each do |row| %>
        <%= render "inbox_row", row: row %>
      <% end %>
```

`<thead>` stays. A `<table>` may contain any number of `<tbody>` elements, which is what makes one-tbody-per-row a legitimate way to give Turbo a stable replace target.

- [ ] **Step 6: Point `render_turbo_update` at the partial the index actually renders**

In `app/controllers/admin/topics_controller.rb`, replace `render_turbo_update` (lines ~172–183):

```ruby
    def render_turbo_update(message)
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            helpers.dom_id(@topic),
            partial: "admin/topics/inbox_row",
            locals: { row: Admin::Topics::InboxQuery.row_for(@topic) }
          )
        }
        format.html { redirect_back fallback_location: admin_topics_path, notice: message }
      end
    end
```

And in the `update` action's `format.turbo_stream` failure branch (lines ~52–62), replace the `partial: "admin/topics/topic"` render with the same shape:

```ruby
          format.turbo_stream {
            render turbo_stream: turbo_stream.replace(
              helpers.dom_id(@topic),
              partial: "admin/topics/inbox_row",
              locals: { row: Admin::Topics::InboxQuery.row_for(@topic) }
            )
          }
```

- [ ] **Step 7: Run the test**

Run: `bin/rails test test/controllers/admin/topics_review_test.rb`
Expected: 9 runs, 0 failures.

- [ ] **Step 8: Run the wider topics suite**

Run: `bin/rails test test/controllers/admin/topics_controller_test.rb test/controllers/admin/topics_controller_description_test.rb`
Expected: pass. `topics_controller_test.rb`'s "index renders inbox rows with repair entrypoint" asserts `assert_select "a[href=?]", admin_topic_path(@topic), text: "Open"` — still satisfied. If it asserts on a `<tr>` directly under `<tbody>` in a way the new nesting breaks, update the assertion; the nesting change is intentional.

- [ ] **Step 9: Confirm in the browser that triage works end to end**

With `bin/dev`, open `/admin/topics?review_status=proposed`, click Approve on a row, and confirm the row updates in place without a full reload.

- [ ] **Step 10: Commit**

```bash
bin/rubocop
git add app/services/admin/topics/inbox_query.rb app/views/admin/topics/_inbox_row.html.erb app/controllers/admin/topics_controller.rb test/controllers/admin/topics_review_test.rb
git commit -m "fix(admin): restore topic triage actions lost in the inbox migration"
```

---

## Task 13: Harvest the inline importance editor

**Files:**
- Modify: `app/views/admin/topics/_inbox_row.html.erb`
- Test: `test/controllers/admin/topics_review_test.rb` (add to it)

**Interfaces:**
- Consumes: the `inline-save` Stimulus controller (`app/javascript/controllers/inline_save_controller.js`, existing) and `Admin::TopicsController#update`, which already permits `:importance`.

`_topic.html.erb` is the only place this ever existed. Port it before Task 15 deletes that file.

- [ ] **Step 1: Write the failing test**

```ruby
    test "each row has an inline importance editor" do
      topic = Topic.create!(name: "importance #{SecureRandom.hex(4)}", status: "approved", review_status: "approved", importance: 3)
      get admin_topics_url

      assert_select "tbody#topic_#{topic.id} form[action=?]", admin_topic_path(topic) do
        assert_select "input[name='topic[importance]'][value='3']"
      end
    end

    test "importance can be saved from the index" do
      topic = Topic.create!(name: "imp save #{SecureRandom.hex(4)}", status: "approved", review_status: "approved", importance: 1)

      patch admin_topic_path(topic), params: { topic: { importance: 7 } }, as: :turbo_stream

      assert_equal 7, topic.reload.importance
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/topics_review_test.rb -n /importance/`
Expected: FAIL — no importance input in the row.

- [ ] **Step 3: Add `importance` to the Row and the query**

`Row` has no `importance` field. Add it to the `Data.define` list in `app/services/admin/topics/inbox_query.rb` and set `importance: topic.importance` in `row_for`.

- [ ] **Step 4: Add the editor column to `_inbox_row`**

Insert this `<td>` immediately before the final actions `<td>`:

```erb
    <td>
      <%= form_with model: [:admin, Topic.new(id: row.topic_id)],
            url: admin_topic_path(row.topic_id),
            method: :patch,
            class: "flex items-center gap-2",
            data: { controller: "inline-save",
                    action: "submit->inline-save#submit turbo:submit-end->inline-save#end" } do |f| %>
        <%= f.number_field :importance, value: row.importance, min: 0, max: 10, class: "form-input w-8" %>
        <%= f.submit "Save", class: "btn btn--sm" %>
      <% end %>
    </td>
```

Add a matching `<th>Importance</th>` to `index.html.erb`'s header row, before the empty trailing `<th>`.

- [ ] **Step 5: Run the tests**

Run: `bin/rails test test/controllers/admin/topics_review_test.rb`
Expected: 11 runs, 0 failures.

- [ ] **Step 6: Commit**

```bash
bin/rubocop
git add app/services/admin/topics/inbox_query.rb app/views/admin/topics/_inbox_row.html.erb app/views/admin/topics/index.html.erb test/controllers/admin/topics_review_test.rb
git commit -m "feat(admin): inline importance editing on the topic inbox"
```

---

## Task 14: Harvest the mention-preview expander

**Files:**
- Modify: `app/views/admin/topics/_inbox_row.html.erb`
- Modify: `app/views/admin/topics/index.html.erb`
- Test: `test/controllers/admin/topics_review_test.rb` (add to it)

**Interfaces:**
- Consumes: the `row-toggle` Stimulus controller (existing), and the helpers `topic_recent_mentions(topic, limit:)`, `topic_mention_preview(agenda_item, topic, window:)`, `highlight_preview_terms(text, terms)`, `preview_window_from_params(params)` — all in `app/helpers/admin/topics_helper.rb` and already used by `_topic.html.erb`.

The preview needs the `Topic` record, not just the Row, because the helpers take a topic and walk its agenda items. Pass the record through rather than widening `Row` with association data.

- [ ] **Step 1: Write the failing test**

```ruby
    test "rows with mentions offer an expandable preview" do
      topic = Topic.create!(name: "mentions #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current,
                                status: "minutes_posted", detail_page_url: "http://example.com/m/#{SecureRandom.hex(6)}")
      item = AgendaItem.create!(meeting: meeting, number: 1, title: "Sidewalk item", order_index: 1)
      AgendaItemTopic.create!(topic: topic, agenda_item: item)

      get admin_topics_url

      assert_select "tbody#topic_#{topic.id} [data-controller='row-toggle']"
      assert_select "tbody#topic_#{topic.id} button[data-action='row-toggle#toggle']"
      assert_select "tbody#topic_#{topic.id} tr[data-row-toggle-target='details'][hidden]"
    end

    test "rows without mentions disable the preview button" do
      topic = Topic.create!(name: "nomentions #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      get admin_topics_url

      assert_select "tbody#topic_#{topic.id} button[disabled]"
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/topics_review_test.rb -n /preview/`
Expected: FAIL — no `row-toggle` controller in the row.

- [ ] **Step 3: Pass the topic record into the partial**

Task 12 already removed the `<tbody>` wrapper. Now widen the render call in `app/views/admin/topics/index.html.erb` so the partial can build previews:

```erb
      <% topics_by_id = Topic.where(id: @inbox_rows.map(&:topic_id))
                             .includes(agenda_items: :meeting)
                             .index_by(&:id) %>
      <% @inbox_rows.each do |row| %>
        <%= render "inbox_row",
              row: row,
              topic: topics_by_id[row.topic_id],
              preview_window: preview_window_from_params(params) %>
      <% end %>
```

The `includes` matters: without it, `topic_recent_mentions` issues two queries per row, and the inbox renders up to 200 rows.

- [ ] **Step 4: Add the expander to `_inbox_row`**

Add `data-controller="row-toggle"` to the `<tbody>` tag, prepend a Preview button to the actions cell, and append the details row before `</tbody>`:

```erb
<tbody id="topic_<%= row.topic_id %>" data-controller="row-toggle">
```

In the actions `<div>`, before the triage buttons:

```erb
        <% has_mentions = row.mention_count.positive? %>
        <button type="button"
                class="btn btn--sm"
                <% if has_mentions %>
                  data-action="row-toggle#toggle"
                  data-row-toggle-target="button"
                  aria-expanded="false"
                  aria-controls="topic_<%= row.topic_id %>_preview"
                <% else %>
                  disabled
                <% end %>>
          Preview
        </button>
```

And immediately before the closing `</tbody>`:

```erb
  <tr id="topic_<%= row.topic_id %>_preview" data-row-toggle-target="details" hidden>
    <td colspan="8">
      <% mentions = topic ? topic_recent_mentions(topic, limit: 3) : [] %>
      <% if mentions.any? %>
        <% mentions.each do |agenda_item| %>
          <% preview = topic_mention_preview(agenda_item, topic, window: preview_window) %>
          <div class="mb-3">
            <div class="font-semibold">
              <%= agenda_item.meeting.body_name %>
              <% if agenda_item.meeting.starts_at.present? %>
                <span class="timestamp"><%= agenda_item.meeting.starts_at.to_date %></span>
              <% end %>
            </div>
            <div class="table-desc"><%= agenda_item.title %></div>
            <% if preview %>
              <div class="adm-panel mt-1">
                <div class="italic"><%= highlight_preview_terms(preview[:text], preview[:terms]) %></div>
                <% if preview[:document_type].present? %>
                  <div class="timestamp">
                    <%= preview[:document_type].to_s.humanize %><%= " · page #{preview[:page_number]}" if preview[:page_number].present? %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      <% else %>
        <p class="table-desc m-0">No recent mentions.</p>
      <% end %>
    </td>
  </tr>
```

`colspan="8"` matches the eight `<th>` cells after Task 13 added Importance. If the header count changes, update it.

- [ ] **Step 5: Handle the turbo replacement path**

`render_turbo_update` renders `_inbox_row` without `topic:` or `preview_window:`. Add defaults at the top of the partial so the replacement path does not raise:

```erb
<% topic = local_assigns[:topic] %>
<% preview_window = local_assigns.fetch(:preview_window, nil) %>
```

- [ ] **Step 6: Run the tests**

Run: `bin/rails test test/controllers/admin/topics_review_test.rb test/controllers/admin/topics_controller_test.rb`
Expected: pass.

- [ ] **Step 7: Commit**

```bash
bin/rubocop
git add app/views/admin/topics/_inbox_row.html.erb app/views/admin/topics/index.html.erb test/controllers/admin/topics_review_test.rb
git commit -m "feat(admin): expandable mention preview on the topic inbox"
```

---

## Task 15: Delete the dead subtree

**Files:**
- Delete: 11 view files (listed below)
- Modify: `config/routes.rb:94-95` — remove the two dead GET routes
- Test: `test/views/admin_view_hygiene_test.rb` (add an orphan guard)

**Interfaces:**
- Everything worth keeping was ported in Tasks 12–14. Nothing here is consumed by anything.

`topic_repairs#show` and `#history` render pages with no inbound link; `topics#show` supersedes them. The POST/PATCH/DELETE actions on `TopicRepairsController` (`merge`, `merge_away`, `topic_to_alias`, `flip_alias`, `move_alias`, `update_alias`, `promote_alias`, `remove_alias`, `retire`) **are** reachable from `topics#show` and must be kept.

- [ ] **Step 1: Write the orphan guard**

Append to `AdminViewHygieneTest`:

```ruby
  test "no admin partial is orphaned" do
    sources = Rails.root.glob("app/{views,controllers}/**/*.{erb,rb}")
    orphans = []

    Rails.root.glob("app/views/admin/**/_*.erb").each do |partial|
      name = partial.basename.to_s.sub(/\A_/, "").sub(/\.html\.erb\z/, "")
      dir  = partial.dirname.relative_path_from(Rails.root.join("app/views")).to_s
      pattern = /render[( ][^\n]*["'](?:#{Regexp.escape(dir)}\/)?#{Regexp.escape(name)}["']|partial:\s*["'](?:#{Regexp.escape(dir)}\/)?#{Regexp.escape(name)}["']/

      referenced = sources.any? { |s| s != partial && s.read.match?(pattern) }
      orphans << partial.relative_path_from(Rails.root).to_s unless referenced
    end

    assert_empty orphans,
      "these partials are rendered by nothing — delete them or wire them up:\n  #{orphans.join("\n  ")}"
  end
```

- [ ] **Step 2: Run it to see the orphans it detects**

Run: `bin/rails test test/views/admin_view_hygiene_test.rb -n /orphaned/`
Expected: FAIL listing `topics/_ai_decisions`, `topics/_history_snapshot`, `topics/_merge_candidates`, `topics/_merge_modal`, and (now that Task 12 stopped rendering it) `topics/_topic`.

This proves the guard detects real orphans before anything is deleted.

- [ ] **Step 3: Delete the dead files**

```bash
git rm app/views/admin/topics/_topic.html.erb \
       app/views/admin/topics/_ai_decisions.html.erb \
       app/views/admin/topics/_history_snapshot.html.erb \
       app/views/admin/topics/_merge_candidates.html.erb \
       app/views/admin/topics/_merge_modal.html.erb \
       app/views/admin/topic_repairs/show.html.erb \
       app/views/admin/topic_repairs/history.html.erb \
       app/views/admin/topic_repairs/_aliases.html.erb \
       app/views/admin/topic_repairs/_surgery.html.erb \
       app/views/admin/topic_repairs/_history.html.erb \
       app/views/admin/topic_repairs/_merge_candidates.html.erb
```

- [ ] **Step 4: Remove the two dead GET routes**

In `config/routes.rb`, delete these two lines from the `resources :topics` member block (lines 94–95):

```ruby
        get :repair, to: "admin/topic_repairs#show"
        get :history, to: "admin/topic_repairs#history"
```

Leave `merge_candidates` and `impact_preview` — both are fetched by the `topic-repair-search` and `topic-detail-impact` Stimulus controllers from `topics#show`. Leave every POST/PATCH/DELETE route in that block.

- [ ] **Step 5: Delete the now-unreachable controller actions**

In `app/controllers/admin/topic_repairs_controller.rb`, remove the `show` and `history` actions and any `before_action` filters that reference only them. Keep every other action.

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: pass, except `test/controllers/admin/topic_repairs_controller_test.rb`, which almost certainly asserts on `#show` or `#history`. Delete only the tests covering those two removed actions; keep every test covering the merge/alias/retire actions.

- [ ] **Step 7: Verify the merge and alias workflows still function**

With `bin/dev`, open a topic at `/admin/topics/:id` and exercise: searching for a duplicate in "This Topic Is Correct", the alias rail, and "This Topic Should Not Exist". None may 404.

- [ ] **Step 8: Commit**

```bash
bin/rubocop
git add -A
git commit -m "refactor(admin): delete the unreachable topic-repair subtree

Superseded by topics#show. The triage buttons, inline importance editor
and mention preview that only existed here were ported in the preceding
three commits before removal."
```

---

## Task 16: Remove the remaining inline styles

**Files:**
- Modify: ~25 admin views
- Test: `test/views/admin_view_hygiene_test.rb` (add the inline-style guard)

**Interfaces:**
- Consumes: the utility layer (Task 6) and components (Tasks 9–11).

51 inline `style="…"` attributes existed at audit time; 6 sat in files Task 15 deleted. The rest are overwhelmingly simple spacing that maps directly onto utilities already defined.

- [ ] **Step 1: Write the guard**

Append to `AdminViewHygieneTest`:

```ruby
  test "no admin view uses an inline style attribute" do
    offenders = VIEWS.filter_map do |path|
      count = path.read.scan(/style="/).length
      "#{path.relative_path_from(Rails.root)} (#{count})" if count.positive?
    end

    assert_empty offenders,
      "inline styles mean a component is missing — grow the component instead:\n  " +
      offenders.join("\n  ")
  end
```

- [ ] **Step 2: Run it to confirm it detects the real violations**

Run: `bin/rails test test/views/admin_view_hygiene_test.rb -n /inline_style/`
Expected: FAIL listing ~25 files with counts. This is the mutation proof — the guard is demonstrably detecting, not passing vacuously.

- [ ] **Step 3: Replace inline styles with utilities, file by file**

Work down the failure list. The full inventory and its mapping:

| Inline style | Replacement |
|---|---|
| `style="margin: 0;"` | `class="m-0"` |
| `style="margin: 0 0 var(--space-2);"` | `class="mb-2"` (already defined in `application.css`) |
| `style="margin: 0 0 var(--space-1);"` | `class="mb-1"` |
| `style="margin-bottom: 0;"` | `class="mb-0"` (already defined) |
| `style="margin-bottom: var(--space-1);"` | `class="mb-1"` |
| `style="margin-bottom: var(--space-2);"` | `class="mb-2"` |
| `style="margin-bottom: var(--space-3);"` | `class="mb-3"` |
| `style="margin-bottom: var(--space-4);"` | `class="mb-4"` |
| `style="margin-top: var(--space-1);"` | `class="mt-1"` |
| `style="margin-top: var(--space-3);"` | `class="mt-3"` |
| `style="margin-top: var(--space-4);"` | `class="mt-4"` |
| `style="margin: var(--space-2) 0 0;"` | `class="mt-2"` |
| `style="padding: var(--space-5);"` | `class="p-6"` (nearest step; `card` already pads) |
| `style="padding: 0;"` | `class="p-0"` — **add `.p-0 { padding: 0; }`** to the utility layer and to `UTILITIES` in the stylesheet test, raising the count assertion from 41 to 42 |
| `style="opacity: 0.5; cursor: not-allowed;"` | delete — `.theme-silo .btn[disabled]` (Task 11) already does this |
| `style="cursor: pointer;"` | `class="cursor-pointer"` |
| `style="display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-2);"` | `class="grid grid-cols-2 gap-2"` |
| `style="font-family: var(--font-data); …"` variants | `class="timestamp"` (Task 7) or `class="data-cell"` |
| `style="font-style: italic; color: …"` | `class="italic text-secondary"` |
| `style="color: var(--color-text-muted); font-style: italic;"` | `class="italic text-muted"` |
| `style="font-weight: 400; color: var(--color-text-muted);"` | `class="text-muted"` |
| `style="border-top: 1px solid var(--color-border); padding-top: var(--space-4);"` | `class="border-t pt-4"` — **add `.pt-4 { padding-top: var(--space-4); }`**, raising the count to 43 |
| `style="padding: var(--space-3) 0; border-bottom: 1px solid var(--color-border);"` | wrap the block in `class="adm-panel"` instead |
| `style="background-color: var(--color-bg); padding: var(--space-2); …"` | `class="adm-panel"` |
| `style="flex: 1; max-width: none;"` | `class="grow"` |
| `style="max-width: 500px;"` | **add `.form-input--wide { max-width: 500px; }`** to the forms component, raising the count to 44 |
| `style="flex-shrink: 0;"` | **add `.shrink-0 { flex-shrink: 0; }`**, raising the count to 45 |
| `style="display:none"` | `hidden` attribute |
| `style="display: block;"` | delete — the element is already block |
| `style="font-size: 0.65rem;"` | delete — `.adm-chip` sets its own size |
| `style="cursor: default; border-left: 3px solid var(--color-primary);"` | `class="adm-table__row--ok"` |
| `style="border-left: none;"` | delete |
| `style="padding-left: var(--space-4); margin: 0;"` | `class="m-0"` plus `.adm-list { padding-left: var(--space-4); }` — **add it**, raising the count to 46 |
| `style="font-size: var(--font-size-base); font-weight: var(--font-weight-semibold); margin-bottom: var(--space-4);"` | `class="text-md font-semibold mb-4"` |
| `style="margin-top: var(--space-1); color: var(--color-text-muted); font-size: var(--text-sm);"` | `class="mt-1 text-muted text-sm"` — note `--text-sm` is a **typo** in the original; the token is `--font-size-sm` |

Update `UTILITIES` and the `assert_equal 41` count in `test/assets/admin_stylesheet_test.rb` as you add each of the six new rules, ending at 46.

- [ ] **Step 4: Run the guard until it is green**

Run: `bin/rails test test/views/admin_view_hygiene_test.rb`
Expected: pass, including the undefined-class guard — adding classes without defining them fails Task 8's test, which is exactly the intended interlock.

- [ ] **Step 5: Run everything**

Run: `bin/rails test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
bin/rubocop
git add -A
git commit -m "refactor(admin): replace inline styles with components and utilities"
```

---

## Task 17: Rename the two misleading job pages, and finish

**Files:**
- Modify: `app/views/admin/jobs/show.html.erb:4`
- Modify: `app/views/admin/job_runs/index.html.erb` (heading already fixed in Task 7)
- Test: `test/controllers/admin/job_runs_controller_test.rb`

`job_runs` is an *enqueue console* with no run history; `jobs` is the queue monitor. The old names said the opposite. `Admin::Navigation` already carries the new labels from Task 1; these are the page headings.

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/admin/job_runs_controller_test.rb`:

```ruby
    test "the enqueue console is titled for what it does" do
      get admin_job_runs_url
      assert_response :success
      assert_match "Run a Job", response.body
      assert_no_match "Job Re-Run Console", response.body
    end

    test "the queue monitor is titled for what it does" do
      get admin_jobs_url
      assert_response :success
      assert_match "Queue &amp; Failures", response.body
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/job_runs_controller_test.rb`
Expected: FAIL — "Job Queue" is the current heading.

- [ ] **Step 3: Rename the queue monitor heading**

In `app/views/admin/jobs/show.html.erb`, replace lines 1–16's header block:

```erb
<div class="adm-page-header">
  <div class="adm-page-header__eyebrow">The Machine</div>
  <div class="page-header-row">
    <div>
      <h1 class="adm-page-header__title">Queue &amp; Failures</h1>
      <p class="adm-page-header__meta">Worker status, pending work, and failed jobs.</p>
    </div>
    <div class="flex gap-2">
      <%= button_to "Clear All Finished", clear_completed_admin_jobs_path, method: :post, class: "btn",
            data: { confirm: "Clear all completed and failed jobs?" } %>
      <% if @failed_count > 0 %>
        <%= button_to "Retry All Failed", retry_all_failed_admin_jobs_path, method: :post, class: "btn btn--primary",
            data: { confirm: "Retry all #{@failed_count} failed jobs?" } %>
      <% end %>
    </div>
  </div>
</div>
```

- [ ] **Step 4: Run the test**

Run: `bin/rails test test/controllers/admin/job_runs_controller_test.rb`
Expected: pass.

- [ ] **Step 5: Run the whole suite and the CI checks**

```bash
bin/rails test
bin/rubocop
bin/ci
```

Expected: all green. Report the actual counts — do not claim success without the output.

- [ ] **Step 6: Final browser walkthrough**

With `bin/dev`, visit every one of the 16 navigation destinations plus `/admin/topics/:id` and `/admin/meetings/:id`. Confirm: no unstyled page, sidebar current-state correct on each, drawer works at 400px, and the public homepage is unchanged.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(admin): name the job pages for what they actually do"
```

---

## Phase 1 Done — What Is Not

Phases 2 and 3 get their own plans. Explicitly **not** in this plan:

- Replacing utilities with components across the 32 views (Phase 2)
- Multi-select Combine on the topics index (Phase 2)
- "Jump to anything" `/` search (Phase 2)
- Document/summary/transcript status columns on `/admin/meetings` (Phase 2)
- Folding "Regenerate All Summaries" into Run a Job (Phase 2)
- Redesigning the generated-image panel (Phase 2)
- Moving `transcript_imports/show`'s inline `<script>` to Stimulus (Phase 2)
- The admin strip on public pages (Phase 3)
- Whisper transcription for CC-disabled videos — the YouTube sign-in problem remains unsolved and is out of scope entirely
- N+1 queries in the index views
- Enabling CSP
