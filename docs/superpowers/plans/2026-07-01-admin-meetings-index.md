# Admin Meetings Index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a discoverable `/admin/meetings` page so admins can find meetings and reach the existing meeting image-management controls.

**Architecture:** Expand the existing admin meetings controller from show-only to index+show. The index lists recent meetings and links each one to the existing `/admin/meetings/:id` workspace, where regeneration/upload controls already live.

**Tech Stack:** Rails controllers/views/routes, Minitest integration tests, existing admin layout and generated image model.

---

## File Structure

- Modify `config/routes.rb`: allow `index` on existing admin meetings resource.
- Modify `app/controllers/admin/meetings_controller.rb`: add `index` query and helper method for image status.
- Create `app/views/admin/meetings/index.html.erb`: admin meetings list with image state and manage-image links.
- Modify `app/views/admin/dashboard/show.html.erb`: add Meetings link to Content section.
- Modify `app/views/layouts/admin.html.erb`: add Meetings to header/footer navigation.
- Modify `test/controllers/admin/meetings_controller_test.rb`: cover index auth, rendering, and links.

### Task 1: Tests for admin meetings index

**Files:**
- Modify: `test/controllers/admin/meetings_controller_test.rb`

- [ ] **Step 1: Add failing tests**

Add these tests after `test "requires admin authentication"`:

```ruby
test "index requires admin authentication" do
  get admin_meetings_url

  assert_redirected_to new_session_path
end

test "admin can list meetings and reach image management" do
  @meeting.generated_images.create!(
    status: "ready",
    purpose: GeneratedImages::Generator::DEFAULT_PURPOSE,
    generated_at: Time.current,
    source_generation_tier: "test"
  )
  sign_in_as_admin

  get admin_meetings_url

  assert_response :success
  assert_select "h1", text: "Meetings"
  assert_select "td", text: "Plan Commission"
  assert_select "td", text: "Plan Commission"
  assert_select ".badge", text: "ready"
  assert_select "a[href=?]", admin_meeting_path(@meeting), text: "Manage image"
end

test "admin dashboard links to meetings" do
  sign_in_as_admin

  get admin_root_url

  assert_response :success
  assert_select "a[href=?]", admin_meetings_path, text: "Meetings"
end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `bin/rails test test/controllers/admin/meetings_controller_test.rb`

Expected: failures/errors because `admin_meetings_url` route or index action does not exist yet.

### Task 2: Add route and controller index

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/admin/meetings_controller.rb`

- [ ] **Step 1: Expand route**

Change:

```ruby
resources :meetings, only: %i[show], controller: "admin/meetings", as: :admin_meetings
```

to:

```ruby
resources :meetings, only: %i[index show], controller: "admin/meetings", as: :admin_meetings
```

- [ ] **Step 2: Add index action**

Replace `app/controllers/admin/meetings_controller.rb` with:

```ruby
module Admin
  class MeetingsController < BaseController
    def index
      @meetings = Meeting
        .includes(:committee, generated_images: { file_attachment: :blob })
        .order(starts_at: :desc, id: :desc)
        .limit(100)
    end

    def show
      @meeting = Meeting.includes(:committee).find(params[:id])
      @meeting_display_name = helpers.clean_meeting_display(@meeting.body_name).presence || "Meeting"
    end
  end
end
```

- [ ] **Step 3: Run tests to verify route/action progress**

Run: `bin/rails test test/controllers/admin/meetings_controller_test.rb`

Expected: index view missing failure.

### Task 3: Add admin meetings index view

**Files:**
- Create: `app/views/admin/meetings/index.html.erb`

- [ ] **Step 1: Create view**

Create `app/views/admin/meetings/index.html.erb`:

```erb
<% content_for(:title) { "Meetings - Admin" } %>

<div class="page-header">
  <h1 class="page-title">Meetings</h1>
  <p class="page-subtitle">Find a meeting and manage its generated image.</p>
</div>

<div class="card mb-6">
  <div class="card-header">
    <h2 class="card-title">Recent meetings</h2>
    <p class="card-subtitle">Open a meeting workspace to regenerate, disable, or upload a replacement image.</p>
  </div>

  <% if @meetings.any? %>
    <div class="table-responsive">
      <table class="table">
        <thead>
          <tr>
            <th>Meeting</th>
            <th>Committee</th>
            <th>Starts</th>
            <th>Status</th>
            <th>Image</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <% @meetings.each do |meeting| %>
            <% meeting_name = clean_meeting_display(meeting.body_name).presence || "Meeting" %>
            <% latest_image = meeting.generated_images.max_by { |image| [image.created_at || Time.zone.at(0), image.updated_at || Time.zone.at(0), image.id || 0] } %>
            <% image_status = latest_image&.status || "missing" %>
            <% badge_class = case image_status
              when "ready" then "badge--success"
              when "processing" then "badge--warning"
              when "failed" then "badge--danger"
              when "disabled" then "badge--default"
              else "badge--default"
            end %>
            <tr>
              <td><%= meeting_name %></td>
              <td><%= meeting.committee&.name.presence || "—" %></td>
              <td><%= meeting.starts_at ? l(meeting.starts_at, format: :short) : "—" %></td>
              <td><%= meeting.status.presence || "—" %></td>
              <td><span class="badge <%= badge_class %>"><%= image_status %></span></td>
              <td><%= link_to "Manage image", admin_meeting_path(meeting), class: "btn btn--secondary btn--sm" %></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <p class="text-secondary">No meetings found.</p>
  <% end %>
</div>
```

- [ ] **Step 2: Run tests**

Run: `bin/rails test test/controllers/admin/meetings_controller_test.rb`

Expected: dashboard link test still fails until navigation is added.

### Task 4: Add admin dashboard and layout links

**Files:**
- Modify: `app/views/admin/dashboard/show.html.erb`
- Modify: `app/views/layouts/admin.html.erb`

- [ ] **Step 1: Add dashboard link**

In `app/views/admin/dashboard/show.html.erb`, add Meetings in the Content list after Topics:

```erb
<li><%= link_to "Topics", admin_topics_path %></li>
<li><%= link_to "Meetings", admin_meetings_path %></li>
<li><%= link_to "Topic Blocklist", admin_topic_blocklists_path %></li>
```

- [ ] **Step 2: Add header nav link**

In `app/views/layouts/admin.html.erb`, add Meetings after Topics:

```erb
<%= link_to "Topics", admin_topics_path, class: ("active" if controller_name == "topics") %>
<%= link_to "Meetings", admin_meetings_path, class: ("active" if controller_name == "meetings") %>
<%= link_to "Committees", admin_committees_path, class: ("active" if controller_name == "committees") %>
```

- [ ] **Step 3: Add footer link**

In the footer links, add Meetings after Topics:

```erb
<%= link_to "Topics", admin_topics_path %>
<%= link_to "Meetings", admin_meetings_path %>
<%= link_to "Committees", admin_committees_path %>
```

- [ ] **Step 4: Run focused tests**

Run: `bin/rails test test/controllers/admin/meetings_controller_test.rb`

Expected: PASS.

### Task 5: Final verification

**Files:**
- No code changes unless tests reveal failures.

- [ ] **Step 1: Run generated image controller tests**

Run: `bin/rails test test/controllers/admin/generated_images_controller_test.rb`

Expected: PASS.

- [ ] **Step 2: Run relevant admin tests together**

Run: `bin/rails test test/controllers/admin/meetings_controller_test.rb test/controllers/admin/generated_images_controller_test.rb`

Expected: PASS.
