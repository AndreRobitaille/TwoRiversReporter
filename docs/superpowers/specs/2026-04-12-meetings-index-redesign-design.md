# Meetings Index Redesign

**Date:** 2026-04-12
**Status:** Design approved
**Scope:** Public meetings index page (`/meetings`) — atomic-era design system revamp

## Problem

The meetings index is the last public page still using a bare data table. It exposes internal pipeline jargon ("Has Minutes", "Has Packet") that means nothing to residents. No visual separation between upcoming and past meetings. No topic context, no headlines, no sense of which meetings are worth clicking into. Residents who try the page once and see a wall of undifferentiated rows won't come back.

## Use Cases

Three resident scenarios drive the design:

1. **"What's coming up?"** — Sunday evening, heard something's happening this week. Need to see upcoming meetings with enough context to decide whether to attend: when, where, what's on the agenda.
2. **"What happened?"** — Neighbor mentioned the council voted on something. Need to find the recent meeting, confirm it's the right one (headline + topics), and click through to the summary.
3. **"Research mode"** — Going to speak at Plan Commission next week. Need to find every time this topic came up before. Knows rough timeframe or committee, needs to search and browse filtered results.

## Design Principles

- **No pipeline jargon.** Residents don't know what "minutes" vs "packet" vs "transcript" means. Headlines are the content signal for past meetings. Topic pills are the preview for upcoming ones. "No summary yet" is the honest empty state.
- **Headlines sell the click.** A meeting card with a headline ("Water rates rise 12% as council splits 4-3") doesn't need a "Has Summary" badge. The headline *is* the proof there's something worth clicking. Its absence is the signal there isn't.
- **Upcoming meetings are the hero.** These are actionable — residents can attend. They get the most visual weight (date slabs).
- **Search is the archive gateway.** No one browses 500+ meetings. Search narrows, then you browse the filtered results.

## Page Structure

### 1. Header

- **Title:** "Meetings" — Outfit 900, uppercase
- **Tagline:** "What happened and what's next" — Space Grotesk, secondary color
- Optional diamond divider below header, before first section. Don't double up with section headers — atom marker headers already create visual breaks.

### 2. Coming Up (section header: atom marker + "Coming Up" + gradient line)

Shows meetings with `starts_at` in the future, up to 21 days out. Section hidden entirely when no upcoming meetings exist.

**Card format: date slab + detail panel** (reuses homepage "Next Up" visual language)

- **Date slab** (left): Bold colored block — terra-cotta (`--color-terra-cotta`) for council meetings (match against `COUNCIL_PATTERNS` or similar), teal (`--color-teal`) for all others. Shows month (DM Mono, uppercase), day number (Outfit 900, large), day-of-week (DM Mono, uppercase).
- **Detail panel** (right): White card with border.
  - Committee name: Outfit 700, uppercase, teal
  - Time + location: DM Mono, xs, secondary color. Format: "6:30 PM · Council Chambers". Location comes from meeting data if available, omit if not.
  - Topic pills: teal background (`--color-primary-light`), teal text. Sourced from meeting's approved topics. Cap at ~5 pills, show "+N more" if overflow.
  - If no agenda posted: "Scheduled — no agenda yet" in muted text instead of pills.

**Sort order:** Chronological ascending (soonest first).

### 3. What Happened (section header: atom marker + "What Happened" + gradient line)

Shows past meetings from the last 21 days. Enough to cover two full meeting cycles.

**Card format: simple cards** with committee name, date, headline, topic pills.

- **Committee name:** Outfit 700, uppercase, teal — left-aligned
- **Date:** DM Mono, xs, secondary — right-aligned, same baseline as committee name
- **Headline:** Space Grotesk, italic, body color. Sourced from `MeetingSummary.generation_data["headline"]`. This is the primary content signal.
- **Topic pills:** warm amber background (`--color-warning-light`), secondary text. Sourced from meeting's approved topics. Keep compact — these are secondary to the headline.
- **No-summary state:** Muted opacity (~0.6). Shows "No summary yet" instead of headline. Still clickable (meeting page may have agenda/documents).

**Sort order:** Reverse chronological (most recent first).

**Clickable:** Entire card is a link to the meeting show page.

### 4. Search the Archive (section header: atom marker + "Find a Meeting" + gradient line)

No results shown by default. Search box with helpful placeholder.

**Search box:**
- Placeholder: "Search by committee, topic, date, or keyword..."
- Full-width within content area, Space Grotesk, standard form styling
- Submit on Enter or search button

**Search matching — must hit usability threshold:**

The search must match across multiple fields to be useful. A search that only hits document text (current behavior) is broken for common queries like "plan commission" or "october 2025".

Fields to search (in priority order):
1. **Committee/body name** — "plan commission", "council", "parks"
2. **Topic names** — topic names associated with the meeting via agenda items
3. **Dates** — recognize month names ("october", "oct"), year numbers ("2025"), and combinations ("october 2025", "oct 2025"). Filter to matching date range.
4. **Document full-text** — existing `MeetingDocument.search`, as fallback

Implementation approach: search body_name and topic names directly (SQL ILIKE or similar). For dates, detect month/year patterns with simple regex and convert to date range filter. Remaining terms fall through to document full-text search. This is not NLP — it's pattern matching on a small set of known formats.

**Result format: compact rows** inside a single card container (borders between rows, not individual cards).

Each row shows:
- Committee name (Outfit 700, small) + date (DM Mono, right-aligned)
- Headline if available (italic, body color)
- Why it matched: highlighted topic pill if matched on topic, brief text snippet if matched on document text
- Muted treatment for results without summaries

**Empty state:** "No meetings found. Try a different spelling, a committee name, or a year like 2025." — not just "No results" with a clear button.

**Pagination:** Show 15-20 results per page. Standard "Show more" button (not infinite scroll).

### 5. Responsive Behavior

- **Date slabs on mobile:** Stack vertically if needed — date slab full-width above detail panel, or shrink slab width. The date needs to stay prominent.
- **Topic pills on mobile:** Wrap naturally. Cap still applies.
- **Search results on mobile:** Full-width rows, date moves below committee name.
- **Coming Up / What Happened cards:** Single column on mobile (already natural since they're not in a grid).

## Data Requirements

### Controller Changes (`MeetingsController#index`)

The controller needs to prepare three collections:

- `@upcoming` — meetings with `starts_at > Time.current`, next 21 days, ordered ascending. Includes: committee, topics (approved), meeting_documents.
- `@recent` — meetings with `starts_at` in the last 21 days, ordered descending. Includes: committee, topics (approved), meeting_summaries, meeting_documents.
- `@search_results` — only populated when `params[:q]` present. Multi-field search (see Search Matching above). Paginated.

### Summary Headlines

Past meeting cards need `MeetingSummary.generation_data["headline"]`. The preferred summary is: `minutes_recap` > `transcript_recap` > `packet_analysis` (same priority as meeting show page). Load via eager loading or a helper that resolves the best summary per meeting.

### Topic Pills

Both upcoming and past meeting cards show approved topics. Source: `meeting.topics.approved` via the existing `has_many :topics, through: :agenda_items` association. Need eager loading to avoid N+1.

### Committee Color

Upcoming date slabs need to know if a meeting is a council meeting (terra-cotta) vs other (teal). Can match against `body_name` patterns or `committee.committee_type` — same approach as the homepage `COUNCIL_PATTERNS`.

## What This Does NOT Include

- **No committee pill filters** — search handles the committee-filtering use case. Pill buttons add UI complexity for marginal benefit with this audience.
- **No advanced date pickers** — text-based date search ("october 2025") is sufficient. A calendar widget would be over-engineering for this audience.
- **No meeting location data** — we don't currently store location. The "Council Chambers" in the mockup is aspirational. If the field doesn't exist, omit it; don't hardcode.
- **No changes to meeting show page** — this is index only.

## CSS

New styles go in `application.css` under a `/* Meetings Index */` section. Reuse existing design tokens and patterns:

- Section headers: reuse `.home-section-header` pattern (atom marker + label + gradient line)
- Date slabs: similar to homepage `.next-up` styling but adapted for the card layout
- Cards/rows: follow existing `.card` patterns with design token colors
- Badges/pills: reuse existing `.badge` and topic pill patterns
- Search form: extend existing `.search-form` styles

## Files to Change

- `app/views/meetings/index.html.erb` — complete rewrite
- `app/controllers/meetings_controller.rb` — new `#index` action with three collections + search
- `app/assets/stylesheets/application.css` — new meetings index section
- Possibly new partials: `meetings/_upcoming_card`, `meetings/_recent_card`, `meetings/_search_result`
