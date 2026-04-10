# Homepage Redesign — "Newspaper Front Page"

**Date:** 2026-04-10
**Status:** Design approved
**Mockup:** `.superpowers/brainstorm/1386395-1775853637/content/homepage-v5.html`
**Scope:** Replace the current homepage layout (topic headline cards + meeting tables) with a newspaper-style information hierarchy.

---

## Problem

The current homepage mirrors the system's data model (topics vs. meetings, past vs. future) rather than how a resident thinks about their city. It presents 10+ items at equal visual weight across four sections, making it hard to quickly find a specific topic or understand what matters most. Meeting tables show institutional scheduling data (committee names, dates) that mean nothing to casual residents.

### Who this is for

Casually interested residents, 35+, many over 60. They arrive from Facebook neighborhood groups with a vague sense of "something's happening with [topic]." They need to find it in ~15 seconds. They are scanners, not studiers. Mobile-heavy. No accounts. No search (yet). See `docs/AUDIENCE.md`.

### Design goal

**Primary (A):** They found the specific thing they came for and clicked through to it.
**Secondary (C):** They found what they came for AND discovered something else they didn't know about.

---

## Information Architecture

Four zones in strict inverted-pyramid priority order. All zones always render (empty states when no data).

### Zone 1 — Top Stories (1-2 items)

The highest-impact topics with recent activity. Each story card shows:

1. **Topic name** — bold, uppercase, Outfit font, colored (terra-cotta for primary, teal for secondary). This is the scan anchor.
2. **Plain-language description** — the topic's `description` field (auto-generated, max 80 chars). Translates government jargon. DM Mono, small, uppercase, muted color.
3. **Briefing headline** — from `TopicBriefing.headline`. 1-2 sentences in editorial voice. Space Grotesk body font.
4. **Meeting reference** — "Apr 6 · Public Utilities Committee". DM Mono metadata.
5. **"Read more →" button** — explicit click affordance. Teal on info-light background, inverts on hover.

**Primary story** gets a large card with heavy shadow, 5px terra-cotta/amber gradient accent bar, starburst motif in corner (8% opacity). **Secondary story** gets a slightly smaller card with teal accent bar.

**Data source:** Top 1-2 approved topics by `resident_impact_score DESC` where `last_activity_at` within 30 days. Minimum impact threshold of 4. If only one topic qualifies at 5, show one. If multiple at the same score, prefer the one with the most recent `last_activity_at`.

**Links to:** Topic show page (`/topics/:id`).

### Zone 2 — The Wire (6-10 items)

Two visual sub-tiers:

**Mid-tier cards (4 items):** 2-column grid of cards, each showing topic name + description + headline + meeting reference + "Read →" link. Cards have 3px teal top accent (50% opacity, full on hover), lift on hover. These are the next 4 topics by impact score after Zone 1.

**Compact rows (remaining items):** A single grouped card containing rows. Each row shows topic name (teal, uppercase) + plain-language description (truncated) + → arrow. On hover: info-light background, arrow slides right. On mobile: descriptions hidden, just topic name + arrow for thumb-friendly tapping.

**Data source:** Approved topics with `last_activity_at` within 30 days and `resident_impact_score >= 2`, ordered by `resident_impact_score DESC, last_activity_at DESC`. Exclude topics already shown in Zone 1. First 4 become mid-tier cards, remainder become compact rows.

**Sort order:** Impact score descending (inverted pyramid), NOT chronological. Meeting date is metadata on each item, not the organizing structure.

**No committee filtering.** All committees are eligible. Subcommittee topics that score high appear naturally — this lets the page surface issues weeks before they reach City Council.

**Links to:** Topic show page (`/topics/:id`).

### Zone 3 — Next Up (1-2 items)

Minimal calendar strip showing the next council meeting and/or work session. Each entry is a card with:

- **Date slab** — colored block (terra-cotta for council, teal for work session) with month and day number in Outfit bold.
- **Meeting name** — uppercase Outfit.
- **Status note** — "Agenda not yet posted" or topic count when available.
- **→ arrow** — explicit click affordance.

Side-by-side on desktop, stacked on mobile. Inset shadow on the date slab for depth.

**Data source:** Next meetings where `body_name` matches City Council Meeting or City Council Work Session patterns, ordered by `starts_at`, limit 2.

**Links to:** Meeting show page (`/meetings/:id`).

### Zone 4 — Escape Hatches

Two skeuomorphic buttons: "Browse All Topics →" and "All Meetings →". Gradient backgrounds (teal to dark teal), inset top highlight, shadow, press-down active state. Stack vertically on mobile.

**Links to:** `/topics` and `/meetings`.

---

## Visual Design

### Design System Compliance

All styling uses design system tokens from `docs/plans/2026-03-28-atomic-design-system-spec.md`:

- **Colors:** `--color-teal`, `--color-terra-cotta`, `--color-amber`, `--color-bg`, `--color-surface`, `--color-border`, `--color-text`, `--color-text-secondary`, `--color-text-muted`, `--color-info-light`
- **Typography:** Outfit (display/headings, always uppercase), Space Grotesk (body/headlines), DM Mono (metadata/descriptions, always uppercase)
- **Shadows:** `--shadow-sm`, `--shadow-md`, `--shadow-lg` with warm-toned rgba
- **Radii:** `--radius-md` (6px), `--radius-lg` (10px)

### Atomic Motifs

- **Starburst** — top-right of primary story card, 8% opacity, terra-cotta rays + teal nucleus
- **Diamond dividers** — between all four zones, terra-cotta with fade-in/out gradient lines
- **Atom markers** — section headers for "The Wire" and "Next Up" (terra-cotta orbits, teal nucleus + trailing gradient line)

### Clickability Affordances

Critical for the 60+ audience. Every interactive element has an explicit visual cue:

- **Story cards:** "Read more →" button (teal on light background, inverts on hover)
- **Wire mid-tier cards:** "Read →" link with underline on hover
- **Wire compact rows:** → arrow that slides right and changes color on hover
- **Next Up cards:** → arrow with same slide behavior
- **Escape buttons:** Gradient background, inset highlight, shadow, press-down state

Entire cards are also clickable (larger tap target), but the visible affordance element is always present.

### Hover/Active States

- **Cards:** translateY(-1px or -2px) lift + shadow elevation
- **Compact rows:** info-light background fill
- **Buttons:** gradient inversion on hover, inset shadow on active
- **Wire card top accents:** opacity 0.5 → 1.0 on hover

### Mobile Behavior (≤600px)

- Nav collapses to hamburger with dropdown menu
- Page title reduces to 1.35rem
- Wire grid goes to 1-column (cards stack)
- Compact row descriptions hidden (topic name + arrow only for thumb tapping)
- Next Up cards stack vertically
- Escape buttons stack vertically, full width
- Card padding reduces slightly throughout

---

## Data Requirements

### New queries needed

The `HomeController` needs restructured queries. Key changes from current:

1. **Zone 1 (top stories):** Replace dual `build_what_happened`/`build_coming_up` with a single query: approved topics, `resident_impact_score >= 4`, `last_activity_at` within 30 days, ordered by score desc then recency, limit 2.

2. **Zone 2 (the wire):** Approved topics, `resident_impact_score >= 2`, `last_activity_at` within 30 days, ordered by score desc then recency, excluding Zone 1 topic IDs. Split results: first 4 → mid-tier cards, remainder → compact rows.

3. **Zone 3 (next up):** Meetings where body_name matches council/work session patterns, `starts_at > Time.current`, ordered by `starts_at`, limit 2.

4. **Topic descriptions:** Needed for all wire items and top stories. `Topic.description` is the field — already auto-generated. If nil, omit the description line (don't show blank space).

5. **Briefing headlines:** Needed for Zone 1 (top stories) and Zone 2 mid-tier cards. Loaded from `TopicBriefing.headline`. If nil, show just topic name + description (no headline text).

6. **Meeting reference:** For each topic, the most recent meeting where it appeared. Derived from `TopicAppearance` joined to `Meeting` — the appearance with the most recent `meeting.starts_at`.

### Removed queries

- `upcoming_meetings_grouped` — full meeting table is gone
- `recent_meetings_grouped` — full meeting table is gone
- `build_coming_up` with `upcoming_headline` — replaced by unified impact-sorted approach
- Meeting diversity filter (`apply_meeting_diversity`) — no longer needed since we're not grouping by upcoming meeting

### Data field dependencies

| Field | Source | Required? |
|-------|--------|-----------|
| Topic name | `Topic.name` | Yes |
| Topic description | `Topic.description` | No (omit if nil) |
| Briefing headline | `TopicBriefing.headline` | No (card still works without it) |
| Impact score | `Topic.resident_impact_score` | Yes (used for sorting/filtering) |
| Last activity | `Topic.last_activity_at` | Yes (used for recency window) |
| Meeting reference | `TopicAppearance` → `Meeting` (most recent) | No (omit if no appearances) |
| Next meeting date | `Meeting.starts_at` | Yes |
| Next meeting body | `Meeting.body_name` | Yes |

---

## What's Removed

- **"What Happened" / "Coming Up" dual card layout** — replaced by unified impact-sorted top stories
- **Full meeting tables** (Upcoming Meetings, Recently Completed) — replaced by minimal Next Up strip
- **Meeting rows** with committee names, topic pills, view buttons — gone from homepage entirely
- **Week grouping logic** (`group_meetings_by_week`, `week_key`, `week_label`) — no longer needed
- **`@coming_up_headlines` / `@what_happened_headlines`** instance variables — replaced by unified briefing headline lookup
- **`home/_meeting_week_group.html.erb`** partial — can be deleted
- **`home/_meeting_row.html.erb`** partial — can be deleted

---

## What's Unchanged

- Site nav bar and footer (from `layouts/application.html.erb`) — no changes needed
- Topic show page, meeting show page — unchanged
- Topics index page — unchanged
- `home/_topic_headline_item.html.erb` partial — replaced, can be deleted
- All backend topic/meeting models — no schema changes
- Topic briefing generation — no changes to `GenerateTopicBriefingJob`
- Impact score calculation — no changes to `SummarizeMeetingJob`

---

## Implementation Notes

### Prod DB sync

Development database needs to be synced from production before implementation to test with real data volumes and impact scores. This will break admin MFA on dev — separate concern to address later.

### Worktree/PR approach

Implementation should use a git worktree and PR workflow for isolation from the main branch.

### Empty states

- **No top stories:** Show an editorial message — "Things are quiet at city hall. Check back after the next council meeting." with the Next Up section prominently below.
- **No wire items:** Omit the section entirely (diamond divider still separates zones).
- **No upcoming council/work session:** Show "No council meetings scheduled" in a muted card.

### Quiet period handling

Between council meetings (up to 2 weeks), the content may feel static. The 30-day `last_activity_at` window ensures topics from the most recent council meeting cluster persist through the quiet period. The inverted pyramid means the most important items stay at top even if they're 10 days old. Meeting references show dates so the user understands recency.

### Future enhancements (out of scope)

- Search/filter on homepage (requires search infrastructure)
- "Subscribe to topic" notifications (requires accounts)
- Dynamic reordering based on trending Facebook referrals (requires analytics)
- Agenda topic pills on Next Up cards when agendas are scraped
