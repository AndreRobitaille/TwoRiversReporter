# Topic Detail Decision Board Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the admin topic detail page into a Silo-styled decision board that separates topic-level repair choices from alias-level repair actions and removes user-facing merge terminology.

**Architecture:** Keep `Admin::TopicsController#show` and `Admin::TopicRepairsController` as the integration points, but replace the current center-plus-rail layout with a single-column decision board composed of focused partials. Reuse the existing repair services where possible, add one explicit topic-level flip action, and drive card expansion plus impact previews through lightweight Stimulus behavior and server-side preview partials.

**Tech Stack:** Rails, ERB partials, Stimulus, existing topic repair services, Minitest, application CSS with the Silo design system.

---

## File Structure

### New files
- `app/javascript/controllers/topic-decision-board_controller.js` — manages which decision card is expanded and keeps one card open at a time on desktop and mobile
- `app/services/topics/flip_alias_service.rb` — swaps a topic with its only alias, making the alias canonical and the current topic name an alias
- `test/services/topics/flip_alias_service_test.rb`

### Existing files to modify
- `app/controllers/admin/topics_controller.rb` — load the new board state defaults for the show page if needed
- `app/controllers/admin/topic_repairs_controller.rb` — add topic-level aliasing and flip actions, tighten preview language, and preserve context redirects
- `app/services/admin/topics/detail_workspace_query.rb` — expose any extra decision-board counts or booleans such as `single_alias?`
- `app/services/admin/topics/impact_preview_query.rb` — add preview language for `topic_to_alias` and `flip_alias`
- `app/views/admin/topics/show.html.erb` — replace the current split layout with the stacked decision board
- `app/views/admin/topics/_header_summary.html.erb` — trim header sprawl and align with Silo hierarchy
- `app/views/admin/topics/_impact_summary.html.erb` — update labels and consequence copy to avoid `merge`
- `app/views/admin/topics/_alias_repair_rail.html.erb` — convert into a main-column decision card partial for alias actions
- `app/views/admin/topics/_canonical_correction.html.erb` — replace with the `This Topic Is Wrong` decision card
- `app/views/admin/topics/_merge_workbench.html.erb` — rename and reshape into the `This Topic Is Correct` decision card
- `app/views/admin/topics/_repair_confirm_modal.html.erb` — update button text and confirmation wording
- `app/assets/stylesheets/application.css` — add decision-board styles, Silo card states, and mobile-safe stacking
- `config/routes.rb` — add routes for topic-level aliasing and flipping if not already present
- `test/integration/admin_topic_detail_workspace_test.rb` — rewrite page expectations around the decision board
- `test/controllers/admin/topic_repairs_controller_test.rb` — add controller coverage for topic-to-alias and flip flows

---

### Task 1: Reshape the page into a single-column decision board shell

**Files:**
- Modify: `app/views/admin/topics/show.html.erb`
- Modify: `app/views/admin/topics/_header_summary.html.erb`
- Modify: `app/assets/stylesheets/application.css`
- Test: `test/integration/admin_topic_detail_workspace_test.rb`

- [ ] **Step 1: Write the failing integration test for the new decision-board shell**

```ruby
test "shows topic detail as a decision board" do
  topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
  TopicAlias.create!(topic: topic, name: "harbor project")

  get admin_topic_url(topic)

  assert_response :success
  assert_match "This Topic Is Correct", response.body
  assert_match "This Topic Is Wrong", response.body
  assert_match "Aliases On This Topic", response.body
  assert_match "This Topic Should Not Exist", response.body
  assert_no_match "Merge Into This Topic", response.body
  assert_no_match "Canonical Correction", response.body
  assert_no_match "Alias Repair", response.body
end
```

- [ ] **Step 2: Run the integration test to verify it fails**

Run: `bin/rails test test/integration/admin_topic_detail_workspace_test.rb -n "/shows topic detail as a decision board/"`
Expected: FAIL because the page still renders the old split layout headings.

- [ ] **Step 3: Replace the page shell with a stacked decision board**

```erb
<%= render "header_summary", workspace: @workspace %>

<div class="topic-decision-board" data-controller="topic-decision-board">
  <%= render "merge_workbench", workspace: @workspace, preview: @impact_preview %>
  <%= render "canonical_correction", workspace: @workspace %>
  <%= render "alias_repair_rail", workspace: @workspace, detail_workspace_context: @detail_workspace_context %>
  <section class="topic-decision-card topic-decision-card--danger" data-topic-decision-board-target="card">
    <h2 class="topic-decision-card__title">This Topic Should Not Exist</h2>
    <p class="topic-decision-card__summary">Use this when this topic should no longer be usable at all.</p>
    <%= render "impact_summary", workspace: @retire_preview %>
    <button type="button" class="btn btn--danger" data-action="click->topic-detail-impact#openRetireConfirm">Retire / Block Topic</button>
  </section>

  <%= render "evidence_snapshot", workspace: @workspace %>
  <%= render "history_snapshot", history: @workspace.recent_history %>

  <details class="card p-6">
    <summary class="font-bold cursor-pointer">Edit details</summary>
    ...
  </details>
</div>
```

- [ ] **Step 4: Trim the header so it stays informational instead of becoming another workflow**

```erb
<div class="page-header topic-board-header">
  <div class="flex items-start justify-between gap-4">
    <div>
      <h1 class="page-title"><%= workspace.topic.name %></h1>
      <% if workspace.signals.any? %>
        <p class="text-sm text-secondary mt-2"><%= workspace.signals.join(" • ") %></p>
      <% end %>
    </div>
    <%= link_to "Back to Topics", admin_topics_path, class: "btn btn--secondary" %>
  </div>

  <div class="topic-board-header__chips mt-3">
    <span class="badge <%= review_badge %>">Review: <%= workspace.topic.review_status.presence || "unknown" %></span>
    <span class="badge <%= status_badge %>">Visibility: <%= workspace.topic.status %></span>
    <span class="badge badge--default">Aliases: <%= workspace.alias_count %></span>
    <span class="badge badge--default">Appearances: <%= workspace.appearance_count %></span>
    <span class="badge badge--default">Summaries: <%= workspace.summary_count %></span>
    <span class="badge badge--default">Last activity: <%= workspace.last_activity_at ? time_ago_in_words(workspace.last_activity_at) + " ago" : "unknown" %></span>
  </div>
</div>
```

- [ ] **Step 5: Add Silo-safe board styles and mobile stacking rules**

```css
.topic-decision-board {
  display: grid;
  gap: var(--space-4);
}

.topic-decision-card {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-sm);
  padding: var(--space-6);
}

.topic-decision-card__title {
  margin-bottom: var(--space-2);
}

.topic-decision-card__summary {
  color: var(--color-text-secondary);
  margin-bottom: var(--space-4);
}

.topic-decision-card--danger {
  border-color: color-mix(in srgb, var(--color-danger) 35%, var(--color-border));
}

@media (max-width: 768px) {
  .topic-decision-board {
    gap: var(--space-3);
  }
}
```

- [ ] **Step 6: Run the integration test again**

Run: `bin/rails test test/integration/admin_topic_detail_workspace_test.rb -n "/shows topic detail as a decision board/"`
Expected: PASS

- [ ] **Step 7: Commit the shell conversion**

```bash
git add app/views/admin/topics/show.html.erb app/views/admin/topics/_header_summary.html.erb app/assets/stylesheets/application.css test/integration/admin_topic_detail_workspace_test.rb
git commit -m "feat: convert topic detail to decision board shell"
```

### Task 2: Turn the current-topic combine flow into the `This Topic Is Correct` card

**Files:**
- Modify: `app/views/admin/topics/_merge_workbench.html.erb`
- Modify: `app/views/admin/topics/_impact_summary.html.erb`
- Modify: `app/controllers/admin/topic_repairs_controller.rb`
- Modify: `app/services/admin/topics/impact_preview_query.rb`
- Test: `test/integration/admin_topic_detail_workspace_test.rb`
- Test: `test/controllers/admin/topic_repairs_controller_test.rb`

- [ ] **Step 1: Write the failing integration test for the renamed current-topic card**

```ruby
test "uses non-merge copy for combining duplicate topics into the current topic" do
  topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
  source = Topic.create!(name: "harbor dredging project", status: "approved", review_status: "approved")

  get admin_topic_url(topic), params: { source_topic_id: source.id }

  assert_response :success
  assert_match "This Topic Is Correct", response.body
  assert_match "Combine Duplicate Topic Here", response.body
  assert_match "Use this when another topic is really the same issue", response.body
  assert_no_match "Merge Into This Topic", response.body
  assert_no_match "Confirm merge", response.body
end
```

- [ ] **Step 2: Run the integration test to verify it fails**

Run: `bin/rails test test/integration/admin_topic_detail_workspace_test.rb -n "/uses non-merge copy for combining duplicate topics into the current topic/"`
Expected: FAIL because the old copy still says `Merge Into This Topic` and `Confirm merge`.

- [ ] **Step 3: Rename the card copy and button text in the partial**

```erb
<section class="topic-decision-card topic-decision-card--active" data-topic-decision-board-target="card">
  <h2 class="topic-decision-card__title">This Topic Is Correct</h2>
  <p class="topic-decision-card__summary">Use this when another topic is really the same issue and should live under this topic.</p>

  <%= form_with url: merge_from_repair_admin_topic_path(workspace.topic), method: :post do %>
    <label class="block mb-2" for="merge-source-search">Find duplicate topic</label>
    <input id="merge-source-search" type="search" class="w-full" placeholder="Search by topic name or alias" ...>
    ...
    <button type="button" class="btn btn--primary" data-action="click->topic-detail-impact#openMergeConfirm">
      Combine duplicate topic here
    </button>
  <% end %>
</section>
```

- [ ] **Step 4: Update preview labels so the impact box also avoids `merge` terminology**

```erb
<h3 class="text-sm font-semibold mb-2">Impact preview</h3>

<p class="text-secondary mb-3"><%= workspace.language %></p>
<p class="text-sm mb-3"><%= workspace.consequence %></p>

<dl class="grid grid-cols-1 gap-2 text-sm">
  <div class="flex justify-between gap-3"><dt class="text-secondary">Topics involved</dt><dd><%= workspace.source_topic.present? ? 2 : 1 %></dd></div>
  <div class="flex justify-between gap-3"><dt class="text-secondary">Aliases moving</dt><dd><%= workspace.alias_count %></dd></div>
  ...
</dl>
```

- [ ] **Step 5: Update the preview language generator for the combine action**

```ruby
when :merge
  language = "This will combine #{source_topic.name} into #{topic.name}. Search, topic pages, summaries, and knowledge-linked content will point to #{topic.name}."
  consequence = "#{source_topic.name} stops standing alone and its aliases, appearances, and summaries move under #{topic.name}."
```

- [ ] **Step 6: Run the renamed-flow tests**

Run: `bin/rails test test/integration/admin_topic_detail_workspace_test.rb -n "/uses non-merge copy for combining duplicate topics into the current topic/" test/controllers/admin/topic_repairs_controller_test.rb -n "/impact preview/"`
Expected: PASS

- [ ] **Step 7: Commit the current-topic card rewrite**

```bash
git add app/views/admin/topics/_merge_workbench.html.erb app/views/admin/topics/_impact_summary.html.erb app/controllers/admin/topic_repairs_controller.rb app/services/admin/topics/impact_preview_query.rb test/integration/admin_topic_detail_workspace_test.rb test/controllers/admin/topic_repairs_controller_test.rb
git commit -m "feat: rename current-topic combine workflow"
```

### Task 3: Replace canonical correction with the `This Topic Is Wrong` card and topic-to-alias flow

**Files:**
- Modify: `app/views/admin/topics/_canonical_correction.html.erb`
- Modify: `app/controllers/admin/topic_repairs_controller.rb`
- Modify: `app/services/admin/topics/impact_preview_query.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/admin/topic_repairs_controller_test.rb`
- Test: `test/integration/admin_topic_detail_workspace_test.rb`

- [ ] **Step 1: Write the failing controller test for making this topic an alias of another topic**

```ruby
test "topic_to_alias moves the topic and its aliases under a destination topic" do
  destination = Topic.create!(name: "harbor restoration", status: "approved", review_status: "approved")
  source = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
  TopicAlias.create!(topic: source, name: "harbor project")

  post topic_to_alias_admin_topic_url(source), params: { destination_topic_id: destination.id, reason: "wrong main topic" }

  assert_redirected_to admin_topic_url(destination)
  assert_includes destination.reload.topic_aliases.pluck(:name), "harbor dredging"
  assert_includes destination.topic_aliases.pluck(:name), "harbor project"
end
```

- [ ] **Step 2: Run the controller test to verify it fails**

Run: `bin/rails test test/controllers/admin/topic_repairs_controller_test.rb -n "/topic_to_alias moves the topic and its aliases under a destination topic/"`
Expected: FAIL with route or action missing.

- [ ] **Step 3: Add the route and controller action for the topic-to-alias flow**

```ruby
member do
  post :topic_to_alias
end
```

```ruby
def topic_to_alias
  if params[:reason].blank?
    redirect_to detail_workspace_url, alert: "Reason is required."
    return
  end

  destination_topic = Topic.find(params[:destination_topic_id])
  if destination_topic == @topic
    redirect_to detail_workspace_url, alert: "Cannot move a topic under itself."
    return
  end

  Topics::MergeService.new(source_topic: @topic, target_topic: destination_topic).call
  record_review_event(destination_topic, "topic_rehomed", params[:reason])

  redirect_to admin_topic_url(destination_topic), notice: "#{@topic.name} is now an alias of #{destination_topic.name}."
end
```

- [ ] **Step 4: Rewrite the old canonical correction partial into the new topic-wrong card**

```erb
<section class="topic-decision-card" data-topic-decision-board-target="card">
  <h2 class="topic-decision-card__title">This Topic Is Wrong</h2>
  <p class="topic-decision-card__summary">Use this when the issue is real, but this record should not be the main topic anymore.</p>

  <%= form_with url: topic_to_alias_admin_topic_path(workspace.topic), method: :post, local: true, class: "space-y-3", data: { controller: "topic-repair-search", topic_repair_search_url_value: merge_candidates_admin_topic_path(workspace.topic, mode: :topic_to_alias), topic_repair_search_action_name_value: "topic_to_alias" } do %>
    <%= hidden_field_tag :destination_topic_id, nil, data: { topic_repair_search_target: "targetId" } %>
    <%= hidden_field_tag :alias_count, workspace.alias_count %>
    <label class="block text-xs text-secondary">Find the real main topic</label>
    <input type="search" class="form-input w-full" placeholder="Search destination topics" data-topic-repair-search-target="input" data-action="input->topic-repair-search#search">
    <div class="rounded bg-base-200 p-3 text-sm" data-topic-repair-search-target="preview">
      Choose a destination topic to preview the change. Any existing aliases on this topic will move with it.
    </div>
    <%= text_area_tag :reason, nil, rows: 3, class: "w-full", required: true, placeholder: "Why is this the wrong main topic?" %>
    <%= submit_tag "Make this topic an alias", class: "btn btn--secondary", disabled: true, data: { topic_repair_search_target: "submit" } %>
  <% end %>
</section>
```

- [ ] **Step 5: Add explicit preview copy for alias transfer in `ImpactPreviewQuery`**

```ruby
when :topic_to_alias
  language = "#{topic.name} will stop being a standalone topic and become an alias of #{source_topic.name}. Any aliases already attached here will move too."
  consequence = "This will move #{alias_count} existing alias #{'entry'.pluralize(alias_count)} plus the current topic name under #{source_topic.name}."
```

- [ ] **Step 6: Add the failing integration test for the new card copy**

```ruby
test "shows topic-level aliasing card with alias-transfer warning" do
  topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
  TopicAlias.create!(topic: topic, name: "harbor project")

  get admin_topic_url(topic)

  assert_response :success
  assert_match "This Topic Is Wrong", response.body
  assert_match "Make This Topic An Alias Of Another Topic", response.body
  assert_match "Any existing aliases on this topic will move with it", response.body
  assert_no_match "Canonical Correction", response.body
end
```

- [ ] **Step 7: Run the topic-wrong tests**

Run: `bin/rails test test/controllers/admin/topic_repairs_controller_test.rb -n "/topic_to_alias/" test/integration/admin_topic_detail_workspace_test.rb -n "/shows topic-level aliasing card with alias-transfer warning/"`
Expected: PASS

- [ ] **Step 8: Commit the topic-wrong flow**

```bash
git add app/views/admin/topics/_canonical_correction.html.erb app/controllers/admin/topic_repairs_controller.rb app/services/admin/topics/impact_preview_query.rb config/routes.rb test/controllers/admin/topic_repairs_controller_test.rb test/integration/admin_topic_detail_workspace_test.rb
git commit -m "feat: add topic-level aliasing decision card"
```

### Task 4: Add `Flip Main Topic With Its Only Alias`

**Files:**
- Create: `app/services/topics/flip_alias_service.rb`
- Modify: `app/services/admin/topics/detail_workspace_query.rb`
- Modify: `app/controllers/admin/topic_repairs_controller.rb`
- Modify: `app/views/admin/topics/_canonical_correction.html.erb`
- Modify: `config/routes.rb`
- Test: `test/services/topics/flip_alias_service_test.rb`
- Test: `test/controllers/admin/topic_repairs_controller_test.rb`
- Test: `test/integration/admin_topic_detail_workspace_test.rb`

- [ ] **Step 1: Write the failing service test for flipping a topic with its only alias**

```ruby
require "test_helper"

module Topics
  class FlipAliasServiceTest < ActiveSupport::TestCase
    test "swaps a topic with its only alias" do
      topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
      only_alias = TopicAlias.create!(topic: topic, name: "harbor restoration")

      flipped_topic = FlipAliasService.new(topic: topic).call

      assert_equal "harbor restoration", flipped_topic.name
      assert_includes flipped_topic.topic_aliases.pluck(:name), "harbor dredging"
      assert_not TopicAlias.exists?(only_alias.id)
    end
  end
end
```

- [ ] **Step 2: Run the service test to verify it fails**

Run: `bin/rails test test/services/topics/flip_alias_service_test.rb`
Expected: FAIL with `uninitialized constant Topics::FlipAliasService`.

- [ ] **Step 3: Implement the minimal flip service with a single-alias guard**

```ruby
module Topics
  class FlipAliasService
    def initialize(topic:)
      @topic = topic
    end

    def call
      raise ArgumentError, "topic must have exactly one alias" unless topic.topic_aliases.count == 1

      alias_record = topic.topic_aliases.first
      old_name = topic.name

      Topic.transaction do
        topic.update!(name: alias_record.name)
        alias_record.destroy!
        topic.topic_aliases.create!(name: old_name)
      end

      topic
    end

    private

    attr_reader :topic
  end
end
```

- [ ] **Step 4: Expose `single_alias?` from the workspace query**

```ruby
Workspace = Data.define(
  :topic,
  :aliases,
  ...,
  :single_alias
)

single_alias: topic.topic_aliases.count == 1
```

- [ ] **Step 5: Add the controller action, route, and card button**

```ruby
member do
  post :flip_alias
end
```

```ruby
def flip_alias
  flipped_topic = Topics::FlipAliasService.new(topic: @topic).call
  record_review_event(flipped_topic, "topic_flipped", params[:reason].presence || "flip main topic with only alias")
  redirect_to admin_topic_url(flipped_topic), notice: "#{flipped_topic.name} is now the main topic."
rescue ArgumentError => e
  redirect_to detail_workspace_url, alert: e.message
end
```

```erb
<% if workspace.single_alias %>
  <%= button_to flip_alias_admin_topic_path(workspace.topic), method: :post, class: "btn btn--secondary" do %>
    <%= hidden_field_tag :reason, "flip main topic with only alias" %>
    Flip main topic with its only alias
  <% end %>
<% end %>
```

- [ ] **Step 6: Add the integration test that the flip action only appears with one alias**

```ruby
test "shows flip action only when topic has exactly one alias" do
  one_alias_topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
  TopicAlias.create!(topic: one_alias_topic, name: "harbor restoration")

  get admin_topic_url(one_alias_topic)
  assert_match "Flip Main Topic With Its Only Alias", response.body

  TopicAlias.create!(topic: one_alias_topic, name: "north pier dredging")
  get admin_topic_url(one_alias_topic)
  assert_no_match "Flip Main Topic With Its Only Alias", response.body
end
```

- [ ] **Step 7: Run the flip tests**

Run: `bin/rails test test/services/topics/flip_alias_service_test.rb test/controllers/admin/topic_repairs_controller_test.rb -n "/flip_alias/" test/integration/admin_topic_detail_workspace_test.rb -n "/shows flip action only when topic has exactly one alias/"`
Expected: PASS

- [ ] **Step 8: Commit the flip action**

```bash
git add app/services/topics/flip_alias_service.rb app/services/admin/topics/detail_workspace_query.rb app/controllers/admin/topic_repairs_controller.rb app/views/admin/topics/_canonical_correction.html.erb config/routes.rb test/services/topics/flip_alias_service_test.rb test/controllers/admin/topic_repairs_controller_test.rb test/integration/admin_topic_detail_workspace_test.rb
git commit -m "feat: add topic flip action for single alias"
```

### Task 5: Convert alias repair from a side rail into the `Aliases On This Topic` card and add one-open-card behavior

**Files:**
- Create: `app/javascript/controllers/topic-decision-board_controller.js`
- Modify: `app/views/admin/topics/_alias_repair_rail.html.erb`
- Modify: `app/views/admin/topics/show.html.erb`
- Modify: `app/assets/stylesheets/application.css`
- Test: `test/integration/admin_topic_detail_workspace_test.rb`

- [ ] **Step 1: Write the failing integration test for alias actions living inside the main decision stack**

```ruby
test "renders aliases inside the main decision board instead of a side rail" do
  topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
  TopicAlias.create!(topic: topic, name: "harbor project")

  get admin_topic_url(topic)

  assert_response :success
  assert_match "Aliases On This Topic", response.body
  assert_match "Leave As Alias", response.body
  assert_match "Move Alias To Another Topic", response.body
  assert_no_match "Alias Repair", response.body
end
```

- [ ] **Step 2: Run the integration test to verify it fails**

Run: `bin/rails test test/integration/admin_topic_detail_workspace_test.rb -n "/renders aliases inside the main decision board instead of a side rail/"`
Expected: FAIL because the page still renders the old side-rail copy.

- [ ] **Step 3: Rewrite the alias partial into the new card copy and structure**

```erb
<section class="topic-decision-card" data-topic-decision-board-target="card">
  <h2 class="topic-decision-card__title">Aliases On This Topic</h2>
  <p class="topic-decision-card__summary">Use this when a name under this topic is wrong, outdated, or should stand on its own.</p>

  <% if workspace.aliases.any? %>
    <div class="topic-alias-list">
      <% workspace.aliases.each do |topic_alias| %>
        <article class="topic-alias-row">
          <div>
            <div class="font-medium"><%= topic_alias.name %></div>
            <div class="text-xs text-secondary">Choose one action for this alias.</div>
          </div>
          <div class="topic-alias-row__actions">
            <span class="badge badge--default">Leave As Alias</span>
            ...
          </div>
        </article>
      <% end %>
    </div>
  <% else %>
    <p class="text-secondary">No aliases to review.</p>
  <% end %>
</section>
```

- [ ] **Step 4: Add a Stimulus controller that keeps one decision card expanded at a time**

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card"]

  connect() {
    this.openFirstCard()
  }

  toggle(event) {
    const nextCard = event.currentTarget.closest("[data-topic-decision-board-target='card']")
    this.cardTargets.forEach((card) => {
      card.dataset.expanded = card === nextCard ? String(card.dataset.expanded !== "true") : "false"
    })
  }

  openFirstCard() {
    if (this.cardTargets.length === 0) return
    if (this.cardTargets.some((card) => card.dataset.expanded === "true")) return

    this.cardTargets[0].dataset.expanded = "true"
  }
}
```

- [ ] **Step 5: Wire the card toggle styling in CSS**

```css
.topic-decision-card[data-expanded="false"] .topic-decision-card__body {
  display: none;
}

.topic-decision-card[data-expanded="true"] {
  border-color: var(--color-primary);
  box-shadow: var(--shadow-md);
}

.topic-alias-row {
  display: flex;
  justify-content: space-between;
  gap: var(--space-3);
  align-items: start;
  padding: var(--space-3) 0;
  border-top: 1px solid var(--color-border);
}

@media (max-width: 768px) {
  .topic-alias-row {
    flex-direction: column;
  }
}
```

- [ ] **Step 6: Run the alias-card tests**

Run: `bin/rails test test/integration/admin_topic_detail_workspace_test.rb -n "/Aliases On This Topic|renders aliases inside the main decision board/"`
Expected: PASS

- [ ] **Step 7: Commit the alias card and board interaction**

```bash
git add app/javascript/controllers/topic-decision-board_controller.js app/views/admin/topics/_alias_repair_rail.html.erb app/views/admin/topics/show.html.erb app/assets/stylesheets/application.css test/integration/admin_topic_detail_workspace_test.rb
git commit -m "feat: move alias repairs into decision board"
```

### Task 6: Run focused verification and polish remaining copy/tests

**Files:**
- Modify: `test/integration/admin_topic_detail_workspace_test.rb`
- Modify: `test/controllers/admin/topic_repairs_controller_test.rb`
- Modify: `app/views/admin/topics/_repair_confirm_modal.html.erb`
- Modify: `app/javascript/controllers/modal_controller.js`

- [ ] **Step 1: Update modal and confirmation text to match the new action vocabulary**

```erb
<button class="btn btn--primary">Combine duplicate topic here</button>
<button class="btn btn--secondary">Make this topic an alias</button>
<button class="btn btn--danger">Retire / Block Topic</button>
```

- [ ] **Step 2: Add regression assertions covering removed copy and mobile-safe structure**

```ruby
assert_no_match "Merge Into This Topic", response.body
assert_no_match "Canonical Correction", response.body
assert_no_match "Alias Repair", response.body
assert_match "topic-decision-board", response.body
assert_match "data-controller=\"topic-decision-board\"", response.body
```

- [ ] **Step 3: Run the focused topic detail test files**

Run: `bin/rails test test/integration/admin_topic_detail_workspace_test.rb test/controllers/admin/topic_repairs_controller_test.rb test/services/topics/flip_alias_service_test.rb`
Expected: PASS

- [ ] **Step 4: Run RuboCop on touched Ruby files**

Run: `bin/rubocop app/controllers/admin/topic_repairs_controller.rb app/services/admin/topics/detail_workspace_query.rb app/services/admin/topics/impact_preview_query.rb app/services/topics/flip_alias_service.rb test/controllers/admin/topic_repairs_controller_test.rb test/integration/admin_topic_detail_workspace_test.rb test/services/topics/flip_alias_service_test.rb`
Expected: no offenses

- [ ] **Step 5: Commit the final polish**

```bash
git add app/views/admin/topics/_repair_confirm_modal.html.erb app/javascript/controllers/modal_controller.js test/integration/admin_topic_detail_workspace_test.rb test/controllers/admin/topic_repairs_controller_test.rb
git commit -m "test: verify topic detail decision board flows"
```

## Self-Review

- **Spec coverage:** The plan covers the four decision cards, Silo single-column layout, no-merge copy rules, topic-to-alias alias-transfer warning, single-alias flip action, alias-level action separation, and mobile-safe stacking.
- **Placeholder scan:** All tasks include concrete files, tests, commands, and code snippets; there are no TBD markers or vague "handle later" steps.
- **Type consistency:** The plan consistently uses `topic_to_alias`, `flip_alias`, `single_alias`, and `Combine Duplicate Topic Here` across tasks instead of mixing alternate names.
