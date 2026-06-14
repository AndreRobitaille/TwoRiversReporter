# Admin Meeting Image Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an admin meeting detail page where editors can regenerate, disable, and upload replacement images for meetings.

**Architecture:** Add a minimal `Admin::MeetingsController#show` and `/admin/meetings/:id` route. The show view provides meeting context and reuses the existing `admin/generated_images/panel` partial, which already supports `Meeting` as a polymorphic imageable through `Admin::GeneratedImagesController`.

**Tech Stack:** Rails 8, ERB views, Minitest integration tests, existing Active Storage-backed `GeneratedImage` model.

---

## File Structure

- Create: `app/controllers/admin/meetings_controller.rb`
  - Responsibility: authenticate through `Admin::BaseController`, load a single `Meeting`, and expose it to the admin show view.
- Create: `app/views/admin/meetings/show.html.erb`
  - Responsibility: display enough meeting context for editors and render the shared generated-image panel for the meeting.
- Create: `test/controllers/admin/meetings_controller_test.rb`
  - Responsibility: prove admin access control and presence of meeting image-management controls.
- Modify: `config/routes.rb:89-96`
  - Responsibility: add a single admin meeting show route under the existing `/admin` scope.

No new image service, model, or public meeting page code should be added. Existing upload/regenerate/disable behavior remains in `Admin::GeneratedImagesController`.

---

### Task 1: Add failing tests for admin meeting access and image controls

**Files:**
- Create: `test/controllers/admin/meetings_controller_test.rb`

- [ ] **Step 1: Create the controller test file**

Add this complete file:

```ruby
require "test_helper"

module Admin
  class MeetingsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "meeting-admin@example.com", password: "password", admin: true, totp_enabled: true)
      @admin.ensure_totp_secret!

      @committee = Committee.create!(name: "Plan Commission")
      @meeting = Meeting.create!(
        body_name: "Plan Commission Meeting",
        meeting_type: "Regular",
        starts_at: Time.zone.local(2026, 6, 14, 18, 30),
        status: "minutes_posted",
        detail_page_url: "https://example.com/meetings/plan-commission-2026-06-14",
        committee: @committee
      )
    end

    test "requires admin authentication" do
      get admin_meeting_url(@meeting)

      assert_redirected_to new_session_path
    end

    test "admin can view meeting image management page" do
      sign_in_as_admin

      get admin_meeting_url(@meeting)

      assert_response :success
      assert_select "h1", text: "Plan Commission"
      assert_select "h2", text: "Meeting details"
      assert_select "dd", text: "Plan Commission"
      assert_select "dd", text: "Regular"
      assert_select "a[href=?]", meeting_path(@meeting), text: "View public meeting"
    end

    test "admin meeting page renders generated image controls" do
      sign_in_as_admin

      get admin_meeting_url(@meeting)

      assert_response :success
      assert_select "h3", text: "Meeting image"
      assert_select "form[action=?][method=post]", regenerate_generated_images_path do
        assert_select "input[name=imageable_type][value=Meeting]", 1
        assert_select "input[name=imageable_id][value=?]", @meeting.id.to_s, 1
        assert_select "textarea[name=custom_prompt]", 1
        assert_select "input[type=submit][value='Queue image']", 1
      end
      assert_select "form[action=?][method=post][enctype='multipart/form-data']", generated_images_path do
        assert_select "label", text: "Upload replacement"
        assert_select "input[type=file][name='generated_image[file]']", 1
        assert_select "input[type=submit][value='Save upload']", 1
      end
    end

    private

      def sign_in_as_admin
        post session_url, params: { email_address: @admin.email_address, password: "password" }
        follow_redirect!

        totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
        post mfa_session_url, params: { code: totp.now }
        follow_redirect!
      end
  end
end
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run:

```bash
bin/rails test test/controllers/admin/meetings_controller_test.rb
```

Expected: FAIL/ERROR because `admin_meeting_url` and/or `Admin::MeetingsController` does not exist yet.

---

### Task 2: Add the admin meeting route and controller

**Files:**
- Modify: `config/routes.rb:89-96`
- Create: `app/controllers/admin/meetings_controller.rb`
- Test: `test/controllers/admin/meetings_controller_test.rb`

- [ ] **Step 1: Add the route**

In `config/routes.rb`, add the meeting route near the other admin resources. The surrounding block should become:

```ruby
    resources :members, only: %i[index show], controller: "admin/members", as: :admin_members do
      member do
        post :create_alias
        delete :destroy_alias
        post :merge
      end
    end

    resources :meetings, only: %i[show], controller: "admin/meetings", as: :admin_meetings

    resources :prompt_templates, controller: "admin/prompt_templates", as: :admin_prompt_templates, only: [ :index, :edit, :update ] do
      member do
        get :diff
        post :test_run
      end
    end
```

- [ ] **Step 2: Add the controller**

Create `app/controllers/admin/meetings_controller.rb`:

```ruby
module Admin
  class MeetingsController < BaseController
    def show
      @meeting = Meeting.includes(:committee, :meeting_documents, :generated_images).find(params[:id])
    end
  end
end
```

- [ ] **Step 3: Run the tests to verify the route/controller exists**

Run:

```bash
bin/rails test test/controllers/admin/meetings_controller_test.rb
```

Expected: tests still fail because the show template is missing.

---

### Task 3: Add the admin meeting show view with generated-image panel

**Files:**
- Create: `app/views/admin/meetings/show.html.erb`
- Test: `test/controllers/admin/meetings_controller_test.rb`

- [ ] **Step 1: Add the show template**

Create `app/views/admin/meetings/show.html.erb`:

```erb
<% meeting_name = clean_meeting_display(@meeting.body_name).presence || "Meeting" %>
<% content_for(:title) { "#{meeting_name} - Admin" } %>

<% if flash[:notice] || flash[:alert] %>
  <div class="flash <%= flash[:alert] ? 'flash--danger' : 'flash--success' %> mb-4" data-controller="auto-hide">
    <%= flash[:alert] || flash[:notice] %>
  </div>
<% end %>

<div class="topic-detail-layout">
  <div class="topic-detail-main">
    <section class="topic-decision-card topic-decision-card--primary">
      <div class="topic-decision-card__panel">
        <div class="topic-panel-label">Admin meeting workspace</div>
        <h1 class="topic-decision-card__title"><%= meeting_name %></h1>
        <p class="text-sm text-secondary" style="margin: var(--space-2) 0 0;">
          Manage the generated image used on this meeting's public page and social previews.
        </p>

        <div class="topic-decision-details__actions" style="margin-top: var(--space-4);">
          <%= link_to "View public meeting", meeting_path(@meeting), class: "btn btn--secondary btn--sm" %>
          <% if @meeting.detail_page_url.present? %>
            <%= link_to "City meeting page", safe_external_url(@meeting.detail_page_url), target: "_blank", rel: "noopener", class: "btn btn--secondary btn--sm" %>
          <% end %>
        </div>
      </div>
    </section>

    <section class="topic-decision-card">
      <div class="topic-decision-card__panel">
        <h2 class="topic-decision-card__title">Meeting details</h2>
        <dl class="generated-image-panel__facts" style="margin-top: var(--space-3);">
          <div class="generated-image-panel__fact"><dt>Body</dt><dd><%= meeting_name %></dd></div>
          <div class="generated-image-panel__fact"><dt>Type</dt><dd><%= @meeting.meeting_type.presence || "—" %></dd></div>
          <div class="generated-image-panel__fact"><dt>Committee</dt><dd><%= @meeting.committee&.name.presence || "—" %></dd></div>
          <div class="generated-image-panel__fact"><dt>Starts at</dt><dd><%= @meeting.starts_at ? l(@meeting.starts_at, format: :long) : "—" %></dd></div>
          <div class="generated-image-panel__fact"><dt>Status</dt><dd><%= @meeting.status.presence || "—" %></dd></div>
          <div class="generated-image-panel__fact"><dt>Meeting ID</dt><dd><%= @meeting.id %></dd></div>
        </dl>
      </div>
    </section>
  </div>

  <aside class="topic-detail-sidebar">
    <%= render "admin/generated_images/panel",
      imageable: @meeting,
      purpose: GeneratedImages::Generator::DEFAULT_PURPOSE,
      title: "Meeting image",
      alt: "Generated image for #{meeting_name}",
      return_to: request.fullpath %>
  </aside>
</div>
```

- [ ] **Step 2: Run the admin meeting controller tests**

Run:

```bash
bin/rails test test/controllers/admin/meetings_controller_test.rb
```

Expected: PASS. If the multipart form assertion fails because Rails emits the `enctype` attribute differently, inspect the response body and adjust only that assertion while preserving coverage for the upload form action and file input.

---

### Task 4: Run related image and meeting regression tests

**Files:**
- Test: `test/controllers/admin/meetings_controller_test.rb`
- Test: `test/controllers/admin/generated_images_controller_test.rb`
- Test: `test/controllers/meetings_controller_test.rb`
- Test: `test/models/generated_image_test.rb`

- [ ] **Step 1: Run focused admin meeting tests**

Run:

```bash
bin/rails test test/controllers/admin/meetings_controller_test.rb
```

Expected: PASS.

- [ ] **Step 2: Run existing generated-image admin tests**

Run:

```bash
bin/rails test test/controllers/admin/generated_images_controller_test.rb
```

Expected: PASS. These tests already cover meeting regenerate, disable, and replacement upload behavior.

- [ ] **Step 3: Run public meeting image regression tests**

Run:

```bash
bin/rails test test/controllers/meetings_controller_test.rb
```

Expected: PASS.

- [ ] **Step 4: Run generated image model tests**

Run:

```bash
bin/rails test test/models/generated_image_test.rb
```

Expected: PASS.

---

### Task 5: Final verification and review

**Files:**
- Review: `config/routes.rb`
- Review: `app/controllers/admin/meetings_controller.rb`
- Review: `app/views/admin/meetings/show.html.erb`
- Review: `test/controllers/admin/meetings_controller_test.rb`

- [ ] **Step 1: Confirm route helper exists**

Run:

```bash
bin/rails routes -g admin_meeting
```

Expected output includes a route like:

```text
admin_meeting GET /admin/meetings/:id(.:format) admin/meetings#show
```

- [ ] **Step 2: Run RuboCop on changed Ruby files**

Run:

```bash
bin/rubocop app/controllers/admin/meetings_controller.rb test/controllers/admin/meetings_controller_test.rb config/routes.rb
```

Expected: no offenses.

- [ ] **Step 3: Inspect the git diff**

Run:

```bash
git diff -- config/routes.rb app/controllers/admin/meetings_controller.rb app/views/admin/meetings/show.html.erb test/controllers/admin/meetings_controller_test.rb docs/superpowers/specs/2026-06-14-admin-meeting-image-management-design.md docs/superpowers/plans/2026-06-14-admin-meeting-image-management.md
```

Expected: diff only contains the admin meeting image-management route, controller, view, tests, spec, and this plan.

- [ ] **Step 4: Commit if requested by the user**

Only commit if the user explicitly asks. If committing, run:

```bash
git add config/routes.rb app/controllers/admin/meetings_controller.rb app/views/admin/meetings/show.html.erb test/controllers/admin/meetings_controller_test.rb docs/superpowers/specs/2026-06-14-admin-meeting-image-management-design.md docs/superpowers/plans/2026-06-14-admin-meeting-image-management.md
git commit -m "Add admin meeting image management"
```

Expected: commit succeeds and includes only the intended files.

---

## Self-Review Notes

- Spec coverage: route, controller, admin view, reused generated-image panel, tests, and deferred existing-image selection are covered.
- Public behavior: unchanged; regression tests cover existing public meeting image rendering.
- Scope: no admin meetings index or media-library selection is included.
- Type/name consistency: uses existing `Meeting`, `GeneratedImage`, `clean_meeting_display`, `meeting_path`, `generated_images_path`, `regenerate_generated_images_path`, and `Admin::BaseController` patterns.
