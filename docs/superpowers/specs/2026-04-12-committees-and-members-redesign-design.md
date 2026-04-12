# Committees & Members Page Redesign

**Date:** 2026-04-12
**Status:** Design approved
**Related issues:** #98 (official relationships/interests), #99 (vote dissent as impact signal)

## Problem

The current `/members` page does double duty as a committee directory and an officials roster. The member show page is a flat vote table with no context. Neither page answers the questions residents actually have:

- **"What does this committee do and who's on it?"** — the index dumps everything on one page with no committee-level detail
- **"Who is this person and how do they vote on things I care about?"** — the show page is a decontextualized spreadsheet

## Design Principles

- **Committees are the unit of power.** Members have no individual authority — they matter in the context of the body they sit on. The information architecture reflects this: committees are the primary object, members are secondary.
- **"All we're doing is saying what we know."** Present facts. No computed judgment stats, no editorial framing on member pages. Dates, votes, splits, attendance counts. Let residents draw conclusions.
- **Topics are the organizing structure.** Even on a member page, votes are grouped by topic — not by meeting date. A resident wants "how did they vote on the concessions stand" not "what happened on March 25."
- **Dissent is rare and meaningful.** In Two Rivers, the norm is consensus. A single no vote on a 9-person council is a strong signal. The design surfaces these moments without editorializing them.

## Routes & Navigation

### New routes

| Route | Controller | Purpose |
|-------|-----------|---------|
| `GET /committees` | `CommitteesController#index` | Committee directory (replaces `/members` as nav entry) |
| `GET /committees/:slug` | `CommitteesController#show` | Individual committee page |
| `GET /members/:id` | `MembersController#show` | Enhanced member profile (existing route) |
| `GET /members` | redirect | 301 redirect to `/committees` |

### Navigation

- Nav label changes from "City Officials" to "Committees"
- Update both header and footer nav links

### Link flow

- Committees index → Committee show (click a committee card)
- Committee show → Member show (click a member name in roster)
- Committee show → Topic show (click a topic in "What They've Been Working On")
- Committee show → Meeting show (click a meeting link in activity context)
- Member show → Committee show (click a committee in memberships)
- Member show → Topic show (click a topic name in voting record)
- Member show → Meeting show (click a vote's motion link)
- Topic/Meeting pages → Member show (from vote tables, where already linked)

## Page 1: Committees Index (`/committees`)

### Purpose

Directory of all committees. A resident scans this to find the body they're interested in and clicks through. No roster on this page — that lives on the committee show page.

### Content structure

1. **Page header** — "Committees" title, subtitle: "The boards and commissions that make decisions in Two Rivers"
2. **Committee connections diagram** — static image (`committee-connections.png`) self-hosted in app assets. Shows governance hierarchy: Council → Subcommittees / Advisory Boards / Standalone bodies / Non-profits. Placed between header and committee cards.
3. **Committee cards grouped by type:**
   - "City Government" (`committee_type: "city"`)
   - "Tax-Funded Organizations" (`committee_type: "tax_funded_nonprofit"`)
   - "Other Organizations" (`committee_type: "external"`)
4. **Each committee card shows:**
   - Committee name (links to show page)
   - "Elected by voters" badge (City Council only)
   - Description (truncated to ~2 lines)
   - Member count (current voting members)
5. **City Council gets full-width featured treatment** — larger card spanning the grid
6. **Other committees in two-column grid** — compact, scannable
7. **Dormant/empty committees** — either omitted from the index or shown in a collapsed "Inactive" section at the bottom. Committees with 0 current members AND dormant/dissolved status should not clutter the main directory.

### Controller data

```ruby
# CommitteesController#index
@committees = Committee.where(status: %w[active dormant])
                       .includes(committee_memberships: :member)
                       .order(:name)
# Group by committee_type, sort: city first, then tax_funded_nonprofit, then external
# City Council sorted first within city group
@member_counts = # current voting members per committee (ended_on: nil, excluding staff/non_voting)
```

### Mobile behavior

Single-column card stack. Diagram scales or scrolls horizontally.

## Page 2: Committee Show (`/committees/:slug`)

### Purpose

A resident clicked a committee name. They want to know: what does this body do, who's on it, and what have they been deciding?

### Content structure

1. **Header** — committee type badge, committee name
2. **Description** — from `Committee.description`. Rendered with safe link support so admins can embed authority source links (e.g., "Established under [Wisconsin Statutes § 62.23](https://docs.legis.wisconsin.gov/...)"). Rendering approach: use a safe markdown-to-HTML renderer or `sanitize` with allowed `<a>` tags — determine the safest approach during implementation.
3. **Current Members** — roster of current voting members (`ended_on: nil`, excluding `staff`/`non_voting` roles). Sorted by role hierarchy: Chair → Vice Chair → council members (cross-referenced from City Council membership) → remaining members alphabetically. Each name links to member show page. Council members serving on subcommittees get a "Council Member" badge.
4. **What They've Been Working On** — recent topics discussed by this committee, with context. Each entry shows:
   - Topic name (links to topic show page)
   - Date of most recent discussion at this committee
   - One-liner context from `MeetingSummary.generation_data["item_details"]` for that topic's agenda item at the most recent meeting
   - Sorted by recency (most recently discussed first)
   - Capped at ~5-8 entries
   - "Browse all topics →" link at bottom (links to topics index, possibly filtered)
5. **Back link** — "← All Committees"

### Data sources for "What They've Been Working On"

Query: approved topics that have at least one `TopicAppearance` at a meeting belonging to this committee, ordered by most recent appearance date. For the context one-liner, look up the meeting's `MeetingSummary.generation_data["item_details"]` and find the entry matching the agenda item (same enrichment pattern as topic show page Record section). If no `item_details` match, fall back to the agenda item title.

### Empty states

- No members: "No current members on record" (possible for dormant committees)
- No topic activity: "No recent activity tracked for this committee" or omit the section

### Committee descriptions — content task

After code ships, review and update `Committee.description` values to match the style and authority language from the WordPress site (https://wpsite.lincolndevotional.com/two-rivers-committees/). Those descriptions included specific statute citations, practical explanations of authority scope, and notes about how the committee relates to Council. This is a content task, not a code task — the rendering infrastructure just needs to support links in the description text.

## Page 3: Member Show (`/members/:id`)

### Purpose

A resident clicked a name from a committee roster or from a vote on a topic/meeting page. They want to know: who is this person, what committees are they on, and how do they vote on things that matter?

### Content structure

1. **Header** — member name
2. **Committees** — current committee memberships, each linking to the committee show page. City Council gets visual emphasis (left border accent). Role shown as badge (Chair, Vice Chair, Member). Sorted: Council first, then by committee name.
3. **Attendance** — one factual sentence: "Present at X of Y recorded meetings across all committees. Excused from Z, absent from W." Computed from `MeetingAttendance` records. If no attendance data, omit this section entirely (don't show an empty state).
4. **Voting Record** — votes grouped by topic. Only shows topic groups that pass **either** filter:
   - **High-impact topics:** `Topic.resident_impact_score >= 3`
   - **Dissent:** this member voted against the majority on at least one motion in the topic group
   - Sorted by most recent vote date per topic group
   - Capped at **5 topic groups** (show the 5 most recent that pass either filter)
   - Each topic group shows:
     - Topic name (links to topic show page)
     - Individual votes within the group, each showing: date, motion description (links to meeting), member's vote (color-coded: green for yes, red for no, muted for abstain/absent), vote split (e.g., "6-3 · Passed")
5. **Other Votes** — collapsed `<details>` element containing all remaining votes (unanimous low-impact topic votes + unlinked procedural votes). Labeled with count, e.g., "Other Votes (34)". Brief explanatory text: "Procedural and routine votes." Chronological order, compact format.
6. **Back link** — "← All Committees"

### Computing the vote split

For each motion, count votes by value (`yes`, `no`) from all `Vote` records on that motion. Display as "Y-N" (e.g., "7-2"). Abstain/absent/recused are not included in the split count but the member's own value is still shown. Motion outcome from `Motion.outcome` shown as "Passed"/"Failed".

### Determining majority for dissent filter

A member dissented if their vote value differs from the majority value on a non-unanimous motion. For a motion with 7 yes and 2 no: yes voters are majority, no voters dissented. Unanimous votes (all yes or all no) have no dissent by definition.

### Topic grouping data flow

```
Vote → Motion (via motion_id)
  → Motion.agenda_item (via agenda_item_id, nullable)
    → AgendaItemTopic (join table)
      → Topic

Votes where Motion.agenda_item_id is nil OR agenda_item has no topics → "Other Votes"
Votes where motion chains to a topic → grouped under that topic
```

### Empty states

- No committees: unlikely but "No committee memberships on record"
- No attendance: omit section
- No topic-linked votes passing filters: omit "Voting Record" section, show only "Other Votes" (expanded, not collapsed, since it's the only section)
- No votes at all: "No voting record found for this official"

## Data Model Changes

### No new models or migrations required

All data needed exists in current schema:
- `Committee` (with `slug` already present)
- `CommitteeMembership` (with `role`, `ended_on`)
- `Member`
- `MeetingAttendance` (with `status`, `attendee_type`)
- `Vote` + `Motion` (with `agenda_item_id`, `outcome`)
- `AgendaItemTopic` + `Topic` (with `resident_impact_score`)
- `MeetingSummary` (with `generation_data["item_details"]`)

### New controller

`CommitteesController` — public, read-only, `index` and `show` actions.

### Static asset

`committee-connections.png` — downloaded from WordPress site, stored in `app/assets/images/`.

## Redirect

`GET /members` → 301 redirect to `/committees`. This preserves any existing links or bookmarks to the old officials page.

`/members/:id` routes remain unchanged — member show pages keep their current URLs.

## What This Design Does NOT Include

These are explicitly deferred:

- **Official relationships and business interests** (#98) — needs its own design for data model and editorial approach
- **Vote dissent as impact signal** (#99) — affects scoring and summaries, separate from display
- **Voting pattern analytics** — no percentages, no "dissent rate," no "alignment score." Just the factual record.
- **Historical committee membership** — showing past committee service. The data exists (`ended_on` populated) but displaying it adds complexity. Can layer on later.
- **Committee attendance breakdown** — showing per-committee attendance rates on the committee show page. Deferred to keep scope tight.
- **Connections diagram as generated SVG** — using the static PNG from WordPress. Regenerating it from data (e.g., `parent_committee_id`) is a future possibility.
- **Frontend design treatment** — Atomic-era visual styling will be applied via the frontend-design skill during implementation. This spec defines structure and behavior only.
