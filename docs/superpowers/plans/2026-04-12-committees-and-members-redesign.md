# Committees & Members Page Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the combined `/members` page with a committees-first architecture: committees index, committee show pages, and enhanced member profiles with topic-grouped voting records.

**Architecture:** New `CommitteesController` with index/show actions becomes the primary public entry point. Existing `MembersController#show` is enhanced with committee memberships, attendance, and topic-grouped voting record. Nav changes from "City Officials" to "Committees." `/members` redirects to `/committees`.

**Tech Stack:** Rails 8.1, server-rendered ERB, existing Committee/Member/Vote models, Kramdown for description rendering, Minitest.

**Design spec:** `docs/superpowers/specs/2026-04-12-committees-and-members-redesign-design.md`

---

### Task 1: Routes, Redirect, and Navigation

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Add committees routes and members redirect**

In `config/routes.rb`, add the committees resource and redirect. Place it before the existing `resources :members` line:

```ruby
resources :committees, only: %i[index show], param: :slug
get "members", to: redirect("/committees", status: 301), as: nil
resources :members, only: %i[show]
```

Note: `as: nil` on the redirect prevents a route name conflict with the old `members_path`. The `resources :members` line changes from `%i[index show]` to `%i[show]` since the index is now a redirect.

- [ ] **Step 2: Update navigation links**

In `app/views/layouts/application.html.erb`, change the nav link (line 66):

```erb
<%= link_to "Committees", committees_path, class: ("active" if controller_name == "committees") %>
```

And the footer link (line 88):

```erb
<%= link_to "Committees", committees_path %>
```

- [ ] **Step 3: Verify routes**

Run: `bin/rails routes | grep -E "committee|member"`

Expected output should show:
- `committees GET /committees(.:format) committees#index`
- `committee GET /committees/:slug(.:format) committees#show`
- `GET /members(.:format) redirect(301, /committees)`
- `member GET /members/:id(.:format) members#show`

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb app/views/layouts/application.html.erb
git commit -m "feat: add committees routes, redirect /members, update nav to Committees"
```

---

### Task 2: CommitteesController and Index View

**Files:**
- Create: `app/controllers/committees_controller.rb`
- Create: `app/views/committees/index.html.erb`
- Create: `test/controllers/committees_controller_test.rb`

- [ ] **Step 1: Write the controller test for index**

Create `test/controllers/committees_controller_test.rb`:

```ruby
require "test_helper"

class CommitteesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @council = Committee.create!(
      name: "City Council",
      slug: "city-council",
      committee_type: "city",
      status: "active",
      description: "The legislative body of the city."
    )
    @plan_commission = Committee.create!(
      name: "Plan Commission",
      slug: "plan-commission",
      committee_type: "city",
      status: "active",
      description: "Reviews zoning changes."
    )
    @nonprofit = Committee.create!(
      name: "Explore Two Rivers",
      slug: "explore-two-rivers",
      committee_type: "tax_funded_nonprofit",
      status: "active"
    )
    @dormant_empty = Committee.create!(
      name: "Old Board",
      slug: "old-board",
      committee_type: "city",
      status: "dormant"
    )

    @council_member = Member.create!(name: "Jane Smith")
    CommitteeMembership.create!(
      committee: @council,
      member: @council_member,
      role: "chair",
      source: "admin_manual"
    )
    @plan_member = Member.create!(name: "Bob Jones")
    CommitteeMembership.create!(
      committee: @plan_commission,
      member: @plan_member,
      source: "admin_manual"
    )
  end

  test "index returns success" do
    get committees_url
    assert_response :success
  end

  test "index shows committees grouped by type" do
    get committees_url
    assert_response :success

    assert_select ".committees-type-label", text: /City Government/
  end

  test "index shows committee names linking to show pages" do
    get committees_url
    assert_response :success

    assert_select "a[href=?]", committee_path(@council.slug), text: /City Council/
  end

  test "index shows member counts" do
    get committees_url
    assert_response :success

    # City Council has 1 member, Plan Commission has 1 member
    assert_select ".committees-member-count", minimum: 2
  end

  test "index excludes dissolved committees" do
    dissolved = Committee.create!(
      name: "Dissolved Board", slug: "dissolved-board",
      committee_type: "city", status: "dissolved"
    )
    get committees_url
    assert_response :success

    assert_select "a[href=?]", committee_path(dissolved.slug), count: 0
  end

  test "members index redirects to committees" do
    get "/members"
    assert_response :redirect
    assert_redirected_to committees_path
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/committees_controller_test.rb`

Expected: FAIL — `CommitteesController` doesn't exist yet.

- [ ] **Step 3: Create the controller**

Create `app/controllers/committees_controller.rb`:

```ruby
class CommitteesController < ApplicationController
  COMMITTEE_TYPE_ORDER = { "city" => 0, "tax_funded_nonprofit" => 1, "external" => 2 }.freeze
  COMMITTEE_TYPE_LABELS = {
    "city" => [ "City Government", "Elected and appointed bodies that make binding decisions for Two Rivers" ],
    "tax_funded_nonprofit" => [ "Tax-Funded Organizations", "Non-profit boards that receive city funding but operate independently" ],
    "external" => [ "Other Organizations", "Independent bodies not directly controlled by the city" ]
  }.freeze

  def index
    committees = Committee.where(status: %w[active dormant])
                          .includes(committee_memberships: :member)

    @committees = committees.sort_by do |c|
      [
        c.name == "City Council" ? 0 : 1,
        COMMITTEE_TYPE_ORDER[c.committee_type] || 99,
        c.name
      ]
    end

    @member_counts = @committees.each_with_object({}) do |c, counts|
      counts[c.id] = c.committee_memberships.count { |cm| cm.ended_on.nil? && !%w[staff non_voting].include?(cm.role) }
    end
  end

  def show
  end
end
```

- [ ] **Step 4: Create the index view**

Create `app/views/committees/index.html.erb`:

```erb
<% content_for(:title) { "Committees - Two Rivers Matters" } %>

<div class="page-header">
  <h1 class="page-title">Committees</h1>
  <p class="page-subtitle">The boards and commissions that make decisions in Two Rivers</p>
</div>

<%= image_tag "committee-connections.png", alt: "Diagram showing how Two Rivers committees relate to each other", class: "committees-diagram" %>

<% current_type = nil %>
<% @committees.each do |committee| %>
  <% next if committee.status == "dormant" && @member_counts[committee.id] == 0 %>

  <% if committee.committee_type != current_type %>
    <% current_type = committee.committee_type %>
    <% label, explanation = CommitteesController::COMMITTEE_TYPE_LABELS[current_type] %>
    <div class="committees-type-divider">
      <h2 class="committees-type-label"><%= label %></h2>
      <p class="committees-type-explanation"><%= explanation %></p>
    </div>
  <% end %>

  <%= link_to committee_path(committee.slug), class: "committees-card #{"committees-card--council" if committee.name == "City Council"}" do %>
    <div class="committees-card-header">
      <div>
        <span class="committees-card-name"><%= committee.name %></span>
        <% if committee.name == "City Council" %>
          <span class="badge badge--primary">Elected by voters</span>
        <% end %>
      </div>
      <span class="committees-member-count"><%= @member_counts[committee.id] %> members</span>
    </div>
    <% if committee.description.present? %>
      <p class="committees-card-desc"><%= truncate(committee.description, length: 150) %></p>
    <% end %>
  <% end %>
<% end %>
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/committees_controller_test.rb`

Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/committees_controller.rb app/views/committees/index.html.erb test/controllers/committees_controller_test.rb
git commit -m "feat: add committees index page with grouped directory"
```

---

### Task 3: Committee Show Page

**Files:**
- Modify: `app/controllers/committees_controller.rb`
- Create: `app/views/committees/show.html.erb`
- Create: `app/helpers/committees_helper.rb`
- Modify: `test/controllers/committees_controller_test.rb`

- [ ] **Step 1: Write tests for committee show**

Add to `test/controllers/committees_controller_test.rb`:

```ruby
test "show returns success" do
  get committee_url(@council.slug)
  assert_response :success
end

test "show displays committee name" do
  get committee_url(@council.slug)
  assert_response :success

  assert_select ".committee-name", text: /City Council/
end

test "show displays current members sorted by role" do
  vice_chair = Member.create!(name: "Alice Vice")
  CommitteeMembership.create!(
    committee: @council, member: vice_chair,
    role: "vice_chair", source: "admin_manual"
  )
  regular = Member.create!(name: "Charlie Regular")
  CommitteeMembership.create!(
    committee: @council, member: regular,
    source: "admin_manual"
  )

  get committee_url(@council.slug)
  assert_response :success

  # Chair should appear first (Jane Smith), then vice chair (Alice Vice), then regular (Charlie Regular)
  names = css_select(".committee-member-name").map { |n| n.text.strip }
  assert_equal "Jane Smith", names.first
  assert_equal "Alice Vice", names.second
end

test "show excludes ended memberships" do
  former = Member.create!(name: "Former Member")
  CommitteeMembership.create!(
    committee: @council, member: former,
    source: "admin_manual", ended_on: 1.month.ago
  )

  get committee_url(@council.slug)
  assert_response :success

  names = css_select(".committee-member-name").map { |n| n.text.strip }
  refute_includes names, "Former Member"
end

test "show displays recent topic activity" do
  meeting = Meeting.create!(
    body_name: "City Council", meeting_type: "Regular",
    starts_at: 3.days.ago, status: "minutes_posted",
    detail_page_url: "http://example.com/show-test",
    committee: @council
  )
  topic = Topic.create!(
    name: "test topic for show", status: "approved",
    lifecycle_status: "active", last_activity_at: 2.days.ago
  )
  item = AgendaItem.create!(meeting: meeting, title: "Test Item")
  AgendaItemTopic.create!(topic: topic, agenda_item: item)

  get committee_url(@council.slug)
  assert_response :success

  assert_select ".committee-activity a", text: /Test Topic For Show/
end

test "show renders description with links" do
  @council.update!(description: 'Established under [WI Stats](https://example.com).')
  get committee_url(@council.slug)
  assert_response :success

  assert_select ".committee-description a[href='https://example.com']", text: "WI Stats"
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/committees_controller_test.rb`

Expected: FAIL — show action not implemented, views don't exist.

- [ ] **Step 3: Create the committees helper**

Create `app/helpers/committees_helper.rb`:

```ruby
module CommitteesHelper
  ROLE_SORT_ORDER = { "chair" => 0, "vice_chair" => 1 }.freeze

  # Sort memberships: chair first, vice chair second, council members third, then alphabetical.
  def sort_memberships(memberships, council_member_ids)
    memberships.sort_by do |cm|
      role_order = ROLE_SORT_ORDER[cm.role] || (council_member_ids.include?(cm.member_id) ? 2 : 3)
      [ role_order, cm.member.name.split.last.downcase ]
    end
  end

  # Render committee description with safe markdown link support.
  # Converts markdown-style links [text](url) to HTML <a> tags.
  # Only allows http/https URLs. All other content is HTML-escaped.
  def render_committee_description(text)
    return "" if text.blank?

    escaped = ERB::Util.html_escape(text)
    # Convert markdown links: [text](url) → <a href="url">text</a>
    with_links = escaped.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do
      link_text = Regexp.last_match(1)
      url = CGI.unescapeHTML(Regexp.last_match(2))
      if url.match?(%r{\Ahttps?://})
        "<a href=\"#{ERB::Util.html_escape(url)}\" target=\"_blank\" rel=\"noopener\">#{link_text}</a>"
      else
        link_text
      end
    end
    simple_format(with_links, {}, sanitize: false)
  end
end
```

- [ ] **Step 4: Implement the show action**

Update `app/controllers/committees_controller.rb`, adding the show method:

```ruby
def show
  @committee = Committee.find_by!(slug: params[:slug])

  @memberships = @committee.committee_memberships
    .where(ended_on: nil)
    .where.not(role: %w[staff non_voting])
    .includes(:member)

  city_council = Committee.find_by(name: "City Council")
  @council_member_ids = if city_council && city_council.id != @committee.id
    city_council.committee_memberships
      .where(ended_on: nil)
      .where.not(role: %w[staff non_voting])
      .pluck(:member_id)
      .to_set
  else
    Set.new
  end

  @recent_topics = load_recent_topics
end
```

Add the private helper method to the controller:

```ruby
private

def load_recent_topics
  Topic.approved
    .joins(agenda_item_topics: { agenda_item: :meeting })
    .where(meetings: { committee_id: @committee.id })
    .select("topics.*, MAX(meetings.starts_at) AS latest_meeting_date")
    .group("topics.id")
    .order("latest_meeting_date DESC")
    .limit(8)
end
```

- [ ] **Step 5: Create the show view**

Create `app/views/committees/show.html.erb`:

```erb
<% content_for(:title) { "#{@committee.name} - Two Rivers Matters" } %>

<div class="page-header">
  <span class="badge badge--default"><%= CommitteesController::COMMITTEE_TYPE_LABELS[@committee.committee_type]&.first %></span>
  <% if @committee.name == "City Council" %>
    <span class="badge badge--primary">Elected by voters</span>
  <% end %>
  <h1 class="page-title committee-name"><%= @committee.name %></h1>
</div>

<% if @committee.description.present? %>
  <div class="committee-description">
    <%= render_committee_description(@committee.description) %>
  </div>
<% end %>

<section class="section">
  <div class="home-section-header">
    <%= render "shared/atom_marker" %>
    <span class="home-section-label">Current Members</span>
    <div class="home-section-line"></div>
    <span class="committees-member-count"><%= @memberships.size %> members</span>
  </div>

  <% if @memberships.any? %>
    <div class="committee-roster">
      <% sort_memberships(@memberships, @council_member_ids).each do |cm| %>
        <div class="committee-member">
          <div class="committee-member-info">
            <%= link_to cm.member.name, member_path(cm.member), class: "committee-member-name" %>
            <span class="committee-member-badges">
              <% if cm.role.present? && cm.role.in?(%w[chair vice_chair]) %>
                <span class="badge badge--primary"><%= cm.role.titleize.tr("_", " ") %></span>
              <% end %>
              <% if @council_member_ids.include?(cm.member_id) %>
                <span class="badge badge--info">Council Member</span>
              <% end %>
            </span>
          </div>
        </div>
      <% end %>
    </div>
  <% else %>
    <p class="section-empty">No current members on record.</p>
  <% end %>
</section>

<section class="section">
  <div class="home-section-header">
    <%= render "shared/atom_marker" %>
    <span class="home-section-label">What They've Been Working On</span>
    <div class="home-section-line"></div>
  </div>

  <% if @recent_topics.any? %>
    <div class="committee-activity">
      <% @recent_topics.each do |topic| %>
        <div class="committee-activity-item">
          <div class="committee-activity-header">
            <%= link_to topic.display_name, topic_path(topic), class: "committee-activity-topic" %>
            <% if topic.respond_to?(:latest_meeting_date) && topic.latest_meeting_date %>
              <span class="committee-activity-date"><%= topic.latest_meeting_date.strftime("%b %-d") %></span>
            <% end %>
          </div>
          <% if topic.description.present? %>
            <p class="committee-activity-desc"><%= truncate(topic.description, length: 160) %></p>
          <% end %>
        </div>
      <% end %>
    </div>
    <div class="committee-activity-footer">
      <%= link_to "Browse all topics →", topics_path %>
    </div>
  <% else %>
    <p class="section-empty">No recent activity tracked for this committee.</p>
  <% end %>
</section>

<%= link_to committees_path, class: "back-link" do %>
  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <line x1="19" y1="12" x2="5" y2="12"></line>
    <polyline points="12 19 5 12 12 5"></polyline>
  </svg>
  All Committees
<% end %>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/committees_controller_test.rb`

Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/committees_controller.rb app/views/committees/show.html.erb app/helpers/committees_helper.rb test/controllers/committees_controller_test.rb
git commit -m "feat: add committee show page with roster and recent topic activity"
```

---

### Task 4: Enhanced Member Show Page — Committees and Attendance

**Files:**
- Modify: `app/controllers/members_controller.rb`
- Modify: `app/views/members/show.html.erb`
- Create: `app/helpers/members_helper.rb`
- Modify or create: test file

- [ ] **Step 1: Write tests for enhanced member show**

Create `test/controllers/members_controller_test.rb`:

```ruby
require "test_helper"

class MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @council = Committee.create!(
      name: "City Council", slug: "city-council",
      committee_type: "city", status: "active"
    )
    @public_works = Committee.create!(
      name: "Public Works Committee", slug: "public-works",
      committee_type: "city", status: "active"
    )
    @member = Member.create!(name: "Doug Brandt")
    CommitteeMembership.create!(committee: @council, member: @member, source: "admin_manual")
    CommitteeMembership.create!(committee: @public_works, member: @member, source: "admin_manual")
  end

  test "show returns success" do
    get member_url(@member)
    assert_response :success
  end

  test "show displays committee memberships" do
    get member_url(@member)
    assert_response :success

    assert_select "a[href=?]", committee_path(@council.slug), text: /City Council/
    assert_select "a[href=?]", committee_path(@public_works.slug), text: /Public Works/
  end

  test "show lists City Council first in committees" do
    get member_url(@member)
    assert_response :success

    committee_names = css_select(".member-committee-name").map { |n| n.text.strip }
    assert_equal "City Council", committee_names.first
  end

  test "show displays attendance when data exists" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 3.days.ago, status: "minutes_posted",
      detail_page_url: "http://example.com/att-test"
    )
    MeetingAttendance.create!(
      meeting: meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )

    get member_url(@member)
    assert_response :success

    assert_select ".member-attendance", text: /Present at 1 of 1/
  end

  test "show omits attendance section when no data" do
    get member_url(@member)
    assert_response :success

    assert_select ".member-attendance", count: 0
  end

  test "show excludes ended memberships" do
    old_committee = Committee.create!(
      name: "Old Committee", slug: "old-committee",
      committee_type: "city", status: "active"
    )
    CommitteeMembership.create!(
      committee: old_committee, member: @member,
      source: "admin_manual", ended_on: 1.month.ago
    )

    get member_url(@member)
    assert_response :success

    committee_names = css_select(".member-committee-name").map { |n| n.text.strip }
    refute_includes committee_names, "Old Committee"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/members_controller_test.rb`

Expected: FAIL — new view elements don't exist yet.

- [ ] **Step 3: Update the members controller**

Replace the `show` action in `app/controllers/members_controller.rb`:

```ruby
def show
  @member = Member.find(params[:id])

  @memberships = @member.committee_memberships
    .where(ended_on: nil)
    .where.not(role: %w[staff non_voting])
    .includes(:committee)
    .sort_by { |cm| [ cm.committee.name == "City Council" ? 0 : 1, cm.committee.name ] }

  @attendance = load_attendance
  @votes = @member.votes.joins(motion: :meeting).includes(motion: :meeting).order("meetings.starts_at DESC")
end
```

Add a private method:

```ruby
def load_attendance
  records = @member.meeting_attendances
  return nil if records.none?

  total = records.count
  present = records.where(status: "present").count
  excused = records.where(status: "excused").count
  absent = records.where(status: "absent").count
  { total: total, present: present, excused: excused, absent: absent }
end
```

Also remove the `index` action entirely from `MembersController` (it's now a redirect in routes). Remove the `COMMITTEE_TYPE_ORDER` constant and `load_committee_topics` private method as well — they're no longer needed.

- [ ] **Step 4: Create the members helper**

Create `app/helpers/members_helper.rb`:

```ruby
module MembersHelper
  def attendance_sentence(attendance)
    parts = [ "Present at #{attendance[:present]} of #{attendance[:total]} recorded meetings" ]
    details = []
    details << "excused from #{attendance[:excused]}" if attendance[:excused] > 0
    details << "absent from #{attendance[:absent]}" if attendance[:absent] > 0
    parts << details.join(", ") if details.any?
    parts.join(". ") + "."
  end
end
```

- [ ] **Step 5: Update the member show view**

Replace `app/views/members/show.html.erb`:

```erb
<% content_for(:title) { "#{@member.name} - Two Rivers Matters" } %>

<div class="page-header">
  <h1 class="page-title"><%= @member.name %></h1>
</div>

<section class="section">
  <div class="home-section-header">
    <%= render "shared/atom_marker" %>
    <span class="home-section-label">Committees</span>
    <div class="home-section-line"></div>
  </div>

  <div class="member-committees">
    <% @memberships.each do |cm| %>
      <%= link_to committee_path(cm.committee.slug), class: "member-committee #{"member-committee--council" if cm.committee.name == "City Council"}" do %>
        <span class="member-committee-name"><%= cm.committee.name %></span>
        <% if cm.role.present? && cm.role.in?(%w[chair vice_chair]) %>
          <span class="badge badge--primary"><%= cm.role.titleize.tr("_", " ") %></span>
        <% elsif cm.committee.name == "City Council" %>
          <span class="badge badge--info">Elected</span>
        <% else %>
          <span class="badge badge--default">Member</span>
        <% end %>
      <% end %>
    <% end %>
  </div>
</section>

<% if @attendance %>
  <section class="section">
    <div class="home-section-header">
      <%= render "shared/atom_marker" %>
      <span class="home-section-label">Attendance</span>
      <div class="home-section-line"></div>
    </div>

    <div class="member-attendance">
      <p><%= attendance_sentence(@attendance) %></p>
    </div>
  </section>
<% end %>

<section class="section">
  <div class="home-section-header">
    <%= render "shared/atom_marker" %>
    <span class="home-section-label">Voting Record</span>
    <div class="home-section-line"></div>
  </div>

  <% if @votes.any? %>
    <div class="table-wrapper">
      <table>
        <thead>
          <tr>
            <th>Date</th>
            <th>Body</th>
            <th>Motion</th>
            <th>Vote</th>
            <th>Outcome</th>
          </tr>
        </thead>
        <tbody>
          <% @votes.each do |vote| %>
            <tr>
              <td><strong><%= vote.motion.meeting.starts_at&.strftime("%b %d, %Y") %></strong></td>
              <td><%= vote.motion.meeting.body_name %></td>
              <td><%= link_to truncate(vote.motion.description, length: 80), meeting_path(vote.motion.meeting) %></td>
              <td><span class="vote-value vote-value--<%= vote.value %>"><%= vote.value.titleize %></span></td>
              <td>
                <span class="badge <%= case vote.motion.outcome&.downcase
                  when 'passed' then 'badge--success'
                  when 'failed' then 'badge--danger'
                  else 'badge--default'
                end %>"><%= vote.motion.outcome&.titleize || "Unknown" %></span>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <p class="section-empty">No voting record found for this official.</p>
  <% end %>
</section>

<%= link_to committees_path, class: "back-link" do %>
  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <line x1="19" y1="12" x2="5" y2="12"></line>
    <polyline points="12 19 5 12 12 5"></polyline>
  </svg>
  All Committees
<% end %>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/members_controller_test.rb`

Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/members_controller.rb app/views/members/show.html.erb app/helpers/members_helper.rb test/controllers/members_controller_test.rb
git commit -m "feat: enhance member show with committee memberships and attendance"
```

---

### Task 5: Topic-Grouped Voting Record on Member Show

**Files:**
- Modify: `app/controllers/members_controller.rb`
- Modify: `app/helpers/members_helper.rb`
- Modify: `app/views/members/show.html.erb`
- Modify: `test/controllers/members_controller_test.rb`

- [ ] **Step 1: Write tests for topic-grouped votes**

Add to `test/controllers/members_controller_test.rb`:

```ruby
test "show groups votes by topic for high-impact topics" do
  meeting = Meeting.create!(
    body_name: "City Council", meeting_type: "Regular",
    starts_at: 3.days.ago, status: "minutes_posted",
    detail_page_url: "http://example.com/vote-group-test"
  )
  topic = Topic.create!(
    name: "important topic", status: "approved",
    lifecycle_status: "active", resident_impact_score: 4,
    last_activity_at: 2.days.ago
  )
  item = AgendaItem.create!(meeting: meeting, title: "Important Item")
  AgendaItemTopic.create!(topic: topic, agenda_item: item)
  motion = Motion.create!(
    meeting: meeting, agenda_item: item,
    description: "Motion to approve important thing",
    outcome: "passed"
  )
  Vote.create!(motion: motion, member: @member, value: "yes")

  get member_url(@member)
  assert_response :success

  assert_select ".member-topic-group", minimum: 1
  assert_select ".member-topic-name", text: /Important Topic/
end

test "show includes topics where member dissented" do
  meeting = Meeting.create!(
    body_name: "City Council", meeting_type: "Regular",
    starts_at: 3.days.ago, status: "minutes_posted",
    detail_page_url: "http://example.com/dissent-test"
  )
  topic = Topic.create!(
    name: "low impact but dissent", status: "approved",
    lifecycle_status: "active", resident_impact_score: 1,
    last_activity_at: 2.days.ago
  )
  item = AgendaItem.create!(meeting: meeting, title: "Dissent Item")
  AgendaItemTopic.create!(topic: topic, agenda_item: item)
  motion = Motion.create!(
    meeting: meeting, agenda_item: item,
    description: "Motion that was controversial",
    outcome: "passed"
  )
  # Member voted no (minority)
  Vote.create!(motion: motion, member: @member, value: "no")
  # Others voted yes (majority)
  other1 = Member.create!(name: "Voter One")
  other2 = Member.create!(name: "Voter Two")
  Vote.create!(motion: motion, member: other1, value: "yes")
  Vote.create!(motion: motion, member: other2, value: "yes")

  get member_url(@member)
  assert_response :success

  assert_select ".member-topic-name", text: /Low Impact But Dissent/
end

test "show puts unlinked votes in other votes section" do
  meeting = Meeting.create!(
    body_name: "City Council", meeting_type: "Regular",
    starts_at: 3.days.ago, status: "minutes_posted",
    detail_page_url: "http://example.com/other-test"
  )
  motion = Motion.create!(
    meeting: meeting,
    description: "Motion to approve consent agenda",
    outcome: "passed"
  )
  Vote.create!(motion: motion, member: @member, value: "yes")

  get member_url(@member)
  assert_response :success

  assert_select ".member-other-votes summary", text: /Other Votes/
end

test "show displays vote split" do
  meeting = Meeting.create!(
    body_name: "City Council", meeting_type: "Regular",
    starts_at: 3.days.ago, status: "minutes_posted",
    detail_page_url: "http://example.com/split-test"
  )
  topic = Topic.create!(
    name: "split vote topic", status: "approved",
    lifecycle_status: "active", resident_impact_score: 4,
    last_activity_at: 2.days.ago
  )
  item = AgendaItem.create!(meeting: meeting, title: "Split Item")
  AgendaItemTopic.create!(topic: topic, agenda_item: item)
  motion = Motion.create!(
    meeting: meeting, agenda_item: item,
    description: "Motion with split vote",
    outcome: "passed"
  )
  Vote.create!(motion: motion, member: @member, value: "yes")
  other = Member.create!(name: "Dissenter")
  Vote.create!(motion: motion, member: other, value: "no")

  get member_url(@member)
  assert_response :success

  assert_select ".member-vote-split", text: /1-1/
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/members_controller_test.rb`

Expected: FAIL — topic-grouped vote view elements don't exist.

- [ ] **Step 3: Update the controller to build topic-grouped vote data**

Replace the show action in `app/controllers/members_controller.rb`:

```ruby
def show
  @member = Member.find(params[:id])

  @memberships = @member.committee_memberships
    .where(ended_on: nil)
    .where.not(role: %w[staff non_voting])
    .includes(:committee)
    .sort_by { |cm| [ cm.committee.name == "City Council" ? 0 : 1, cm.committee.name ] }

  @attendance = load_attendance

  all_votes = @member.votes
    .joins(motion: :meeting)
    .includes(motion: [ :meeting, :votes, { agenda_item: { agenda_item_topics: :topic } } ])
    .order("meetings.starts_at DESC")

  @topic_groups, @other_votes = build_vote_groups(all_votes)
end
```

Add to the private section:

```ruby
def build_vote_groups(votes)
  topic_votes = Hash.new { |h, k| h[k] = { topic: nil, votes: [], latest_date: nil, qualifies: false } }
  other_votes = []

  votes.each do |vote|
    topics = vote.motion.agenda_item&.agenda_item_topics&.map(&:topic)&.select { |t| t.status == "approved" }

    if topics.blank?
      other_votes << vote
      next
    end

    topics.each do |topic|
      group = topic_votes[topic.id]
      group[:topic] = topic
      group[:votes] << vote
      meeting_date = vote.motion.meeting.starts_at
      group[:latest_date] = meeting_date if group[:latest_date].nil? || meeting_date > group[:latest_date]

      # Qualifies if high-impact OR member dissented on this motion
      if topic.resident_impact_score && topic.resident_impact_score >= 3
        group[:qualifies] = true
      end

      unless group[:qualifies]
        vote_counts = vote.motion.votes.group(:value).count
        majority_value = vote_counts.max_by { |_, count| count }&.first
        total = vote_counts.values.sum
        majority_count = vote_counts[majority_value] || 0
        # Non-unanimous AND this member is in the minority
        if majority_value && vote.value != majority_value && majority_count < total
          group[:qualifies] = true
        end
      end
    end
  end

  qualified = topic_votes.values
    .select { |g| g[:qualifies] }
    .sort_by { |g| g[:latest_date] }
    .reverse
    .first(5)

  # Move non-qualifying topic votes into other_votes
  qualified_topic_ids = qualified.map { |g| g[:topic].id }.to_set
  topic_votes.each do |topic_id, group|
    unless qualified_topic_ids.include?(topic_id)
      other_votes.concat(group[:votes])
    end
  end
  other_votes.sort_by! { |v| v.motion.meeting.starts_at }.reverse!

  [ qualified, other_votes ]
end
```

- [ ] **Step 4: Add vote split helper**

Add to `app/helpers/members_helper.rb`:

```ruby
def vote_split(motion)
  counts = motion.votes.group(:value).count
  yes_count = counts["yes"] || 0
  no_count = counts["no"] || 0
  "#{yes_count}-#{no_count}"
end

def vote_color_class(value)
  case value
  when "yes" then "vote-value--yes"
  when "no" then "vote-value--no"
  else "vote-value--neutral"
  end
end
```

- [ ] **Step 5: Update the voting record section of the view**

Replace the voting record section in `app/views/members/show.html.erb` (the `<section>` that contains the table) with:

```erb
<section class="section">
  <div class="home-section-header">
    <%= render "shared/atom_marker" %>
    <span class="home-section-label">Voting Record</span>
    <div class="home-section-line"></div>
  </div>

  <% if @topic_groups.any? %>
    <% @topic_groups.each do |group| %>
      <div class="member-topic-group">
        <h3 class="member-topic-name">
          <%= link_to group[:topic].display_name, topic_path(group[:topic]) %>
        </h3>
        <div class="member-topic-votes">
          <% group[:votes].each do |vote| %>
            <div class="member-vote-row">
              <div class="member-vote-motion">
                <span class="member-vote-date"><%= vote.motion.meeting.starts_at&.strftime("%b %-d") %></span>
                <%= link_to truncate(vote.motion.description, length: 100), meeting_path(vote.motion.meeting) %>
              </div>
              <div class="member-vote-result">
                <span class="vote-value <%= vote_color_class(vote.value) %>"><%= vote.value.titleize %></span>
                <span class="member-vote-split"><%= vote_split(vote.motion) %> · <%= vote.motion.outcome&.titleize || "Unknown" %></span>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
  <% end %>

  <% if @other_votes.any? %>
    <details class="member-other-votes">
      <summary>Other Votes (<%= @other_votes.size %>)</summary>
      <p class="member-other-votes-desc">Procedural and routine votes.</p>
      <div class="member-other-votes-list">
        <% @other_votes.each do |vote| %>
          <div class="member-vote-row member-vote-row--compact">
            <div class="member-vote-motion">
              <span class="member-vote-date"><%= vote.motion.meeting.starts_at&.strftime("%b %-d") %></span>
              <%= link_to truncate(vote.motion.description, length: 80), meeting_path(vote.motion.meeting) %>
            </div>
            <span class="vote-value <%= vote_color_class(vote.value) %>"><%= vote.value.titleize %></span>
          </div>
        <% end %>
      </div>
    </details>
  <% end %>

  <% if @topic_groups.empty? && @other_votes.empty? %>
    <p class="section-empty">No voting record found for this official.</p>
  <% end %>
</section>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/members_controller_test.rb`

Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/members_controller.rb app/views/members/show.html.erb app/helpers/members_helper.rb test/controllers/members_controller_test.rb
git commit -m "feat: group member votes by topic, filter by impact and dissent"
```

---

### Task 6: Sitemap Update and Static Asset

**Files:**
- Modify: `app/controllers/sitemaps_controller.rb`
- Modify: `app/views/sitemaps/show.xml.erb`
- Add: `app/assets/images/committee-connections.png`

- [ ] **Step 1: Download the committee connections diagram**

```bash
curl -sL -o app/assets/images/committee-connections.png "https://wpsite.lincolndevotional.com/wp-content/uploads/2025/01/Committee-connections.png"
```

Verify it downloaded:

```bash
file app/assets/images/committee-connections.png
```

Expected: `PNG image data, 4000 x 1999`

- [ ] **Step 2: Update SitemapsController**

Add committees to `app/controllers/sitemaps_controller.rb`:

```ruby
def show
  expires_in 1.hour, public: true

  @topics   = Topic.publicly_visible.order(:id)
  @meetings = Meeting.order(:id)
  @members  = Member.order(:id)
  @committees = Committee.where(status: %w[active dormant]).order(:id)

  respond_to do |format|
    format.xml
  end
end
```

- [ ] **Step 3: Update sitemap view**

Add to `app/views/sitemaps/show.xml.erb`, after the members URL entry (line 27) and before the `@topics.each` loop:

```erb
  <url>
    <loc><%= committees_url %></loc>
    <changefreq>weekly</changefreq>
    <priority>0.8</priority>
  </url>
<% @committees.each do |committee| %>
  <url>
    <loc><%= committee_url(committee.slug) %></loc>
    <lastmod><%= committee.updated_at.iso8601 %></lastmod>
    <changefreq>weekly</changefreq>
    <priority>0.7</priority>
  </url>
<% end %>
```

- [ ] **Step 4: Run the sitemap test**

Run: `bin/rails test test/controllers/sitemaps_controller_test.rb`

Expected: PASS (or update test if it asserts specific URL counts).

- [ ] **Step 5: Commit**

```bash
git add app/assets/images/committee-connections.png app/controllers/sitemaps_controller.rb app/views/sitemaps/show.xml.erb
git commit -m "feat: add committee connections diagram and update sitemap"
```

---

### Task 7: Clean Up Old Members Index View and Run Full Suite

**Files:**
- Delete: `app/views/members/index.html.erb`
- Run: full test suite

- [ ] **Step 1: Remove the old members index view**

```bash
rm app/views/members/index.html.erb
```

This view is no longer rendered — the `/members` route redirects to `/committees`.

- [ ] **Step 2: Run full test suite**

Run: `bin/rails test`

Expected: All tests PASS. If any existing tests reference `members_url` (the index), they'll need updating to use `committees_url` instead.

- [ ] **Step 3: Run CI checks**

Run: `bin/ci`

Expected: PASS (rubocop, brakeman, bundler-audit, importmap audit).

- [ ] **Step 4: Fix any failures**

If tests referencing `members_url` fail, update them to use `committees_url`. If other tests break, investigate and fix.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove old members index view, fix test suite"
```

---

### Task 8: Frontend Design Treatment

**Files:**
- Modify: `app/assets/stylesheets/application.css` (or new committees.css)
- Possibly modify view templates for design refinements

- [ ] **Step 1: Invoke the frontend-design skill**

Use the `frontend-design` skill to apply Atomic-era visual styling to all three pages (committees index, committee show, member show). The structural HTML is in place from prior tasks — this task is purely visual: CSS, spacing, typography, responsive behavior.

Reference the design spec at `docs/plans/2026-03-28-atomic-design-system-spec.md` for color tokens, typography roles, and component patterns.

- [ ] **Step 2: Start dev server and verify in browser**

Run: `bin/dev`

Visit `/committees`, click through to a committee show page, click through to a member show page. Verify the visual treatment matches the Atomic-era design system across all three pages and on mobile viewport widths.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/ app/views/committees/ app/views/members/
git commit -m "style: apply Atomic-era design to committees and member pages"
```
