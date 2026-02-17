# Issue #25: Topic-First "This Week" Homepage

## Status: DRAFT — Awaiting approval

## Summary

Replace the flat meeting table homepage (`meetings#index` at root) with a
topic-first dashboard that answers "what's happening in Two Rivers city
government right now?" The homepage becomes a curated briefing; the existing
meetings index stays at `/meetings` as the full archive and search tool.

---

## Architecture Decision: Hybrid (Option C)

**Homepage (`/` → `home#index`)** — A purpose-built dashboard with topic
signal cards at top and time-windowed meeting lists below. No search bar here;
this is a browsing/scanning experience.

**Meetings archive (`/meetings` → `meetings#index`)** — Stays as-is. Full
chronological table with document search. Becomes the "research tool" for
residents who want to dig into history.

**Rationale:**
- The 30-day/14-day window for a small city contains ~8-15 meetings total.
  That's scannable without filtering UI.
- Search across meeting documents is a different intent than "what's happening."
- Keeps both experiences focused rather than a compromise of both.

---

## Page Layout

```
┌─────────────────────────────────────────────────┐
│  Site Header (unchanged)                        │
├─────────────────────────────────────────────────┤
│                                                 │
│  Compact intro line (NO hero)                   │
│  "What's happening in Two Rivers city           │
│   government" + "Search all meetings →" link    │
│                                                 │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌─ Worth Watching ──────┐ ┌─ Recent Signals ─┐ │
│  │ Topics with upcoming  │ │ Topics with new  │ │
│  │ agenda appearances +  │ │ continuity events│ │
│  │ highlight signals     │ │ in last 30 days  │ │
│  └───────────────────────┘ └─────────────────┘ │
│                                                 │
├─────────────────────────────────────────────────┤
│                                                 │
│  Upcoming Meetings (next 30 days)               │
│  Grouped by week, each meeting shows:           │
│  date | body | topic tags | doc status          │
│                                                 │
├─────────────────────────────────────────────────┤
│                                                 │
│  Recently Completed (past 14 days)              │
│  Same format, with outcome signals:             │
│  date | body | topic tags | votes/minutes       │
│                                                 │
│  "Search all meetings →" link                   │
│                                                 │
├─────────────────────────────────────────────────┤
│  Footer (unchanged)                             │
└─────────────────────────────────────────────────┘
```

---

## Detailed Component Specs

### 1. Intro Line

No hero section. Single line of descriptive text + a link to `/meetings`:
```
What's happening in Two Rivers city government
[Search all meetings →]
```

### 2. Topic Cards (two-column grid on desktop, stacked on mobile)

#### Worth Watching
- **Data source:** `Topic.publicly_visible.active` (or `.recurring`) that
  have a `TopicAppearance` joined to a `Meeting` with `starts_at` in the
  future. Plus any topics with recent highlight signals (agenda_recurrence,
  cross_body_progression, deferral_signal).
- **Display:** Topic name, lifecycle badge, next meeting date + body name,
  highlight signal badges if any.
- **Limit:** 5 topics max. Sorted by next appearance date (soonest first).
- **Empty state:** "No active topics with upcoming meetings."
- **Links:** Each topic links to `topic_path(topic)`.

#### Recent Signals
- **Data source:** Topics with `TopicStatusEvent` records in the last 30 days,
  using the same `HIGHLIGHT_EVENT_TYPES` and labeling logic from
  `TopicsController#build_highlight_signals`.
- **Display:** Topic name, lifecycle badge, signal badges, time since event.
- **Limit:** 5 topics max. Sorted by most recent event.
- **Empty state:** "No recent topic activity detected."
- **Links:** Each topic links to `topic_path(topic)`.

### 3. Upcoming Meetings (next 30 days)

- **Data source:** `Meeting.where(starts_at: Time.current..30.days.from_now)`
  with eager-loaded topics, documents, summaries, motions.
- **Grouping:** By week. Labels: "This Week", "Next Week", then
  "Mon DD – Mon DD" for subsequent weeks.
- **Per meeting row:** Date/time, body name, topic tags (small `.tag` links),
  document status badges, link to meeting detail.
- **Empty state:** "No upcoming meetings scheduled."

### 4. Recently Completed (past 14 days)

- **Data source:** `Meeting.where(starts_at: 14.days.ago..Time.current)`
  with same eager loads.
- **Grouping:** By week. Labels: "This Past Week", "Last Week", then dated
  ranges going back.
- **Per meeting row:** Date, body name, topic tags, document/minutes status,
  vote count if any, summary badge if available.
- **Empty state:** "No recent meetings."
- **Footer:** "Search all meetings →" link to `/meetings`.

---

## Implementation Plan

### Step 1: Add Meeting scopes

Add time-window scopes to `Meeting` model:

```ruby
scope :upcoming, -> { where("starts_at > ?", Time.current).order(starts_at: :asc) }
scope :recent, -> { where("starts_at <= ?", Time.current).order(starts_at: :desc) }
scope :in_window, ->(from, to) { where(starts_at: from..to) }
```

### Step 2: Rewrite HomeController

Replace the existing stub `HomeController#index` with real queries:

```ruby
class HomeController < ApplicationController
  def index
    @worth_watching = build_worth_watching
    @recent_signals = build_recent_signals
    @upcoming_meetings = upcoming_meetings_grouped
    @recent_meetings = recent_meetings_grouped
  end

  private

  # Topics with upcoming agenda appearances + highlight signals
  def build_worth_watching
    # Topics appearing on future meeting agendas
    topic_ids_on_upcoming = TopicAppearance
      .joins(:meeting)
      .where(meetings: { starts_at: Time.current.. })
      .select(:topic_id).distinct

    # Also include topics with recent highlight signals
    topic_ids_with_signals = TopicStatusEvent
      .where(evidence_type: HIGHLIGHT_EVENT_TYPES)
      .where(occurred_at: SIGNAL_WINDOW.ago..)
      .select(:topic_id).distinct

    Topic.publicly_visible
         .where(id: topic_ids_on_upcoming)
         .or(Topic.publicly_visible.where(id: topic_ids_with_signals))
         .where(lifecycle_status: %w[active recurring])
         .limit(5)
    # + attach next_appearance and signal data
  end

  # Topics with recent continuity events
  def build_recent_signals
    # Reuse highlight_signals logic from TopicsController
    ...
  end

  def upcoming_meetings_grouped
    Meeting.where(starts_at: Time.current..30.days.from_now)
           .includes(:meeting_documents, :meeting_summaries, :motions,
                     agenda_items: { agenda_item_topics: :topic })
           .order(starts_at: :asc)
           .group_by { |m| week_label(m.starts_at, :future) }
  end

  def recent_meetings_grouped
    Meeting.where(starts_at: 14.days.ago..Time.current)
           .includes(:meeting_documents, :meeting_summaries, :motions,
                     agenda_items: { agenda_item_topics: :topic })
           .order(starts_at: :desc)
           .group_by { |m| week_label(m.starts_at, :past) }
  end
end
```

### Step 3: Update routes

```ruby
root "home#index"
# meetings#index stays at /meetings (already there)
```

### Step 4: Build view partials

Create these partials under `app/views/home/`:

- `index.html.erb` — Page skeleton with intro line + section containers
- `_worth_watching.html.erb` — Topic card with upcoming appearance info
- `_recent_signals.html.erb` — Topic card with signal badges
- `_meeting_week_group.html.erb` — Week header + meeting rows
- `_meeting_row.html.erb` — Single meeting with topic tags and status badges

Reuse existing CSS classes: `.card`, `.card-grid`, `.badge`, `.tag`,
`.section`, `.section-header`, and topic helpers from `TopicsHelper`.

### Step 5: Extract shared highlight_signals logic

The `build_highlight_signals` method currently lives in `TopicsController`.
Extract it to a concern or module (e.g., `Topics::HighlightSignals`) so both
`TopicsController` and `HomeController` can use it without duplication.

### Step 6: Update nav active state

The layout currently marks nav links active based on `controller_name`. Add
an `active` state for the home link (the site logo already links to root, but
the "Meetings" nav link currently activates on root since root = meetings).
After the change, root is `home`, so no nav link will be active on the
homepage, which is correct — or add explicit "Home" nav item if desired.

### Step 7: Write tests

- `test/controllers/home_controller_test.rb`:
  - Renders successfully with no data (empty states)
  - Shows worth watching topics that have upcoming appearances
  - Shows recent signals from TopicStatusEvents
  - Groups upcoming meetings by week
  - Groups recent meetings by week
  - Shows topic tags on meeting rows
  - Does not show meetings outside the time windows
  - Does not show blocked/proposed topics in worth watching

### Step 8: Verify as litmus test

After implementation, manually inspect:
- Are topic tags appearing on meeting rows? (validates topic extraction)
- Is "Worth Watching" populated with meaningful topics? (validates continuity)
- Are signal badges showing? (validates lifecycle analysis)
- Does the data feel current and accurate? (validates overall pipeline)

---

## Files to Create

| File | Purpose |
|------|---------|
| `app/views/home/index.html.erb` | Rewrite existing stub |
| `app/views/home/_worth_watching.html.erb` | Topic card partial |
| `app/views/home/_recent_signals.html.erb` | Topic card partial |
| `app/views/home/_meeting_week_group.html.erb` | Week group partial |
| `app/views/home/_meeting_row.html.erb` | Meeting row partial |
| `test/controllers/home_controller_test.rb` | Controller tests |

## Files to Modify

| File | Change |
|------|--------|
| `app/models/meeting.rb` | Add time-window scopes |
| `app/controllers/home_controller.rb` | Full rewrite with real queries |
| `config/routes.rb` | Change root route to `home#index` |
| `app/controllers/topics_controller.rb` | Extract shared highlight logic |
| `app/views/layouts/application.html.erb` | Fix nav active state |

## Files Unchanged

- `app/views/meetings/index.html.erb` — Stays as full archive
- `app/assets/stylesheets/application.css` — Existing classes sufficient
- All models except `Meeting` — No schema changes needed

---

## Risks and Mitigations

**Risk:** Topics are poorly extracted or named, making cards useless.
**Mitigation:** This is the point — the homepage becomes a live readout of
topic system quality. Empty or bad data surfaces the problem.

**Risk:** No upcoming meetings in the 30-day window (e.g., holiday break).
**Mitigation:** Each section has a clear empty state. Page still works.

**Risk:** `build_worth_watching` query is slow with joins.
**Mitigation:** All relevant columns are indexed. Topic count is small
(dozens, not thousands). Can add caching later if needed.

---

## Non-Goals

- No search on homepage (that's `/meetings`)
- No filtering or date pickers (the window is deliberate)
- No new CSS framework or design system changes
- No schema migrations
- No changes to topic extraction or AI pipeline
