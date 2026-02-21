# Issue #30: Curated Active Topics Index

## Context

The topics index currently shows all approved topics in a flat paginated list with a "Recently Updated" hero row of 6. This serves neither casual browsers nor researchers well.

After discussion, we identified two distinct use cases:
- **Casual browsing**: "What's being talked about right now?" (this issue)
- **Deep research**: Cross-referencing bodies, timeframes, resolved topics (#62)

This issue focuses on casual browsing only.

## Design

### Hero section — "What Matters Now"
- Active topics with activity in the last 30 days, ranked by `resident_impact_score` DESC
- Capped at 6 cards
- These topics are excluded from the list below (no duplicates)

### Main list — remaining active topics
- All other active topics not in the hero, paginated (20/page, Turbo Stream "Show more")
- Sorted by `last_activity_at DESC`

### Explanation + escape hatch
- Brief text: "Topics currently under discussion in Two Rivers"
- Link: "Looking for older or resolved topics? Explore the full archive" → placeholder research view page (#62)

### Research view placeholder (#62)
- Minimal page: heading, explanation that the feature is coming, back link
- Just enough to not be a dead end

### What stays the same
- Card layout, contents, signal badges, lifecycle badges
- Pagination mechanics (Pagy + Turbo Stream)
- Dark mode support

### What this does NOT include
- No filter bar, dropdowns, or chips
- No body/timeframe filtering (deferred to #62)
- No changes to topic show pages

## Scope of change

- `TopicsController#index` — change base scope to active-only, split hero vs. main list with dedup
- `app/views/topics/index.html.erb` — update hero heading, add explanation text and escape hatch link
- `app/views/topics/index.turbo_stream.erb` — ensure pagination still works with active-only scope
- New route + minimal controller/view for research placeholder
- Tests for new behavior
