# Issue #32: Highlight Newly Active / Resurfaced Topics

## Summary

Add lightweight visual indicators to the Topics index that draw attention to **continuity shifts** — topics that have recently become active, resurfaced after dormancy/resolution, or show structural signals like deferral or cross-body progression.

Per Topic Governance: signals must be structural (recurrence, deferral, return after dormancy), not rhetorical or sentiment-based.

## Current State

The Topics index already has:
- A "Recently Updated" cross-status row (top 6 by `last_activity_at`)
- Lifecycle-grouped sections (active → recurring → dormant → resolved)
- Per-card: topic name, agenda item count, "Updated X ago" timestamp
- Lifecycle badge helper exists (`topic_lifecycle_badge`) but is **not used** on the index cards

What's missing:
- No way to distinguish a topic that just *resurfaced* from one that was already active
- No visual signal for continuity-relevant events (deferral, body change, recurring after resolution)
- The "Recently Updated" section treats all recent activity equally — no emphasis on shifts

## Design

### 1. Identify "highlight-worthy" topics (controller)

Query recent `TopicStatusEvent` records to find topics with meaningful continuity shifts in a rolling window (default: 30 days). Highlight-worthy event types:

| Event Type | Label | Why It Matters |
|---|---|---|
| `agenda_recurrence` | "Resurfaced" | Previously resolved topic is back |
| `deferral_signal` | "Deferral Observed" | Item was deferred/tabled |
| `cross_body_progression` | "Moved Bodies" | Progressed between governing bodies |
| `disappearance_signal` | "Disappeared" | Vanished without resolution |
| `rules_engine_update` to `active` | "Newly Active" | Status just changed to active |

The controller builds a `@highlight_signals` hash: `{ topic_id => [signal_labels] }` from recent `TopicStatusEvent` rows.

### 2. Render signal badges on topic cards (view)

On each topic card in **both** the "Recently Updated" section and the lifecycle-grouped sections, render small badge(s) if the topic has highlights:

```erb
<% if (signals = @highlight_signals[topic.id]) %>
  <div class="card-signals">
    <% signals.each do |signal| %>
      <span class="badge badge--outline badge--signal"><%= signal %></span>
    <% end %>
  </div>
<% end %>
```

Also add the lifecycle badge to every card (it already exists in the helper but isn't rendered on the index).

### 3. Add subtle card accent for highlighted topics (CSS)

Add a `.card--highlighted` modifier with a left border accent. No animation, no color saturation — just a quiet structural cue:

```css
.card--highlighted {
  border-left: 3px solid var(--color-primary);
}

.card-signals {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-1);
  margin-top: var(--space-2);
}

.badge--outline {
  background: transparent;
  border: 1px solid currentColor;
}
```

### 4. Add lifecycle badge to each card

Use the existing `topic_lifecycle_badge` helper in each card header alongside the topic name. This gives every card a structural status indicator.

## Files to Change

| File | Change |
|---|---|
| `app/controllers/topics_controller.rb` | Add `@highlight_signals` query in `index` action |
| `app/views/topics/index.html.erb` | Add lifecycle badges, signal badges, and `.card--highlighted` class |
| `app/helpers/topics_helper.rb` | Add `highlight_signal_label(event_type, lifecycle_status)` helper |
| `app/assets/stylesheets/application.css` | Add `.card--highlighted`, `.card-signals`, `.badge--outline` styles |
| `test/controllers/topics_controller_test.rb` | Add tests for highlight signals rendering |

## Implementation Steps

1. **Helper**: Add `highlight_signal_label` method to `TopicsHelper` that maps event types to human-readable labels.
2. **Controller**: Query `TopicStatusEvent` from the last 30 days, group by topic_id, map to labels via the helper, and assign to `@highlight_signals`.
3. **View**: On each topic card, conditionally add `.card--highlighted` class and render signal badges. Add lifecycle badge to card header.
4. **CSS**: Add the three new style rules (`.card--highlighted`, `.card-signals`, `.badge--outline`).
5. **Tests**: Verify that a topic with a recent `agenda_recurrence` event renders the "Resurfaced" badge, and that a topic without events renders no highlight.

## What This Does NOT Include

- No new database columns or migrations
- No new models or services
- No JavaScript/Stimulus changes
- No changes to the topic detail page (that's separate)
- No importance-based ranking (that's a different concern)

## Governance Compliance

- All signals are structural: recurrence, deferral, body progression, disappearance
- No rhetorical or sentiment-based emphasis
- Labels describe observed patterns, not intent ("Deferral Observed" not "Stalled")
- Consistent with Topic Governance §4 (structural importance), §6 (silence/deferral handling), §7 (no motive attribution)
