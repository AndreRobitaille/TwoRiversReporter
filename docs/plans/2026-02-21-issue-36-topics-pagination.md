# Issue #36: Topics Index Pagination

## Problem

The topics index loads all 103+ publicly visible topics in a single query with
joins, grouping, and highlight signal computation. This causes extremely long
page load times and will only worsen as topic count grows.

The current lifecycle-status section grouping (Active Topics, Dormant Topics,
etc.) adds cognitive overhead for casual residents who don't think in lifecycle
categories — especially when nearly all topics are in one group.

## Design

### Page structure

1. **"Recently Updated" hero** (unchanged) — Top 6 topics by last activity,
   card grid. Orientation point for casual visitors.

2. **"All Topics" flat list** — All publicly visible topics sorted by
   `last_activity_at DESC`. Lifecycle status shown as a badge on each card
   (not as section groupings). First batch: 20 topics.

3. **"Show more" button** — Loads the next 20 topics, appends them inline.
   Uses a Turbo Frame that replaces itself with new cards + a fresh "show more"
   frame if more remain.

4. **Count indicator** — "Showing N of M topics" so the resident knows there's
   more content available.

### Key decisions

- **Flat list, not grouped sections.** Lifecycle status is a per-card badge,
  not a section header. Residents browse by recency, not by lifecycle category.
- **"Show more" button, not page numbers.** Mobile-friendly, no need to
  scroll past 20 cards to find pagination controls. Feels like one expanding
  page, not a multi-page document.
- **Hero duplicates are fine.** The same topics may appear in both "Recently
  Updated" and the flat list. The hero is orientation; the list is exhaustive.
- **No activity window cutoff.** Recency sorting naturally pushes old topics
  down. Activity window filtering deferred to #30 (filters).

### Performance improvements

- Initial query drops from ~103 → 20 rows (Pagy LIMIT/OFFSET).
- Highlight signals computed only for the 20 visible topics, not all.
- `@grouped_topics` eliminated — no more `.to_a.group_by` loading everything
  into memory.
- Subsequent "show more" loads are lightweight Turbo Frame responses (no full
  page layout re-render).

### Tech

- **Pagy gem** — Lightweight pagination. Provides offset/limit, metadata
  (total count, has_more), and helpers.
- **Turbo Frame** — Wraps the "show more" button area. Response appends new
  topic cards + a new frame. No custom Stimulus controller needed.
- **URL state** — `/topics?page=2` for bookmarkability, but the UX is a
  single expanding page.

## Out of scope

- Filtering by lifecycle status, body, or timeframe (#30)
- Lifecycle status chip redesign (#42)
- Empty/error states (#33)
