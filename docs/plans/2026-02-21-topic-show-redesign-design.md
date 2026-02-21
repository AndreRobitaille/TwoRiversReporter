# Topic Show Page Redesign

## Problem

The current topic show page dumps a raw reverse-chronological timeline of every
appearance and status event. It reads like a database log. Residents don't know
what they're looking at — it's noise, not information.

## Audience

Two Rivers residents who:
- **Newcomers**: Clicked a topic name and want to understand what it is and why
  it matters.
- **Followers**: Already know about this topic and want an update on recent and
  upcoming activity.

These are not technically adept people or government experts. They grew up here,
care about the place, and want to hold leaders accountable.

## Design Principles

- Lead with plain language, not system jargon.
- No lifecycle badges, impact scores, timestamps, or internal status labels on
  the resident-facing page. Those are admin concepts.
- Show what matters: what is this, what's the city doing, what happened, and
  how can I participate.
- Link to meetings for full detail — don't replicate everything inline.
- If a section has no data, omit it entirely. No "No data found" cards unless
  the page would otherwise be completely empty.

## Page Structure

### 1. Header — "What is this?"

- Topic name (h1)
- Description in plain, neighborly language
- No badges, no dates, no scores

### 2. Coming Up (conditional — only if future meetings exist)

Show upcoming meeting(s) where this topic is on the agenda:
- Body name, date, time, location
- Agenda item title if available
- Note if there's a public comment period (derive from agenda item title
  containing "public hearing" or "public comment")
- Gentle participation nudge: "You can always contact your council members
  about this topic."
- Link to the meeting page

If no upcoming meetings reference this topic, omit this section entirely.

**Data source**: Topic appearances where `meeting.starts_at > Time.current`,
joined through agenda items.

### 3. What's Happening (conditional — only if topic summary exists)

The most recent TopicSummary content rendered as readable prose or bullets.

- Strip the internal section headers (Factual Record, Institutional Framing,
  Civic Sentiment). Render the content as a unified narrative.
- If multiple summaries exist (one per meeting), show only the most recent.
- If no TopicSummary exists, omit this section.

**Data source**: `topic.topic_summaries.order(created_at: :desc).first`

### 4. Recent Activity

The last ~3 meetings where something substantive happened:
- Filter to appearances that have a motion, vote, or agenda item summary —
  not just "mentioned in packet."
- Each entry: body name, date, one-line agenda item title, outcome if there
  was a motion (e.g., "Approved 5-2"), link to meeting page.
- Compact card or list format, not a full timeline.

If nothing substantive exists, fall back to the last 3 appearances regardless,
showing body name + date + link.

If no appearances at all, show a minimal message: "This topic hasn't appeared
in any meetings yet."

**Data source**: Topic appearances with eager-loaded agenda items, motions.

### 5. Key Decisions (conditional — only if motions/votes exist)

A focused accountability section:
- Each motion: date, body name, description, outcome badge (Passed/Failed),
  vote breakdown (member name + vote value).
- Ordered by date descending.
- This is the section where residents can see how their representatives voted.

If no motions exist for this topic, omit this section entirely.

**Data source**: Motions through `agenda_items` → `agenda_item_topics`, with
votes and members eager-loaded.

### 6. Footer

- "Back to Topics" link

## What's Removed

- Raw timeline dump of every appearance and status event
- TopicStatusEvent rendering ("Rules Engine Update", "Disappearance Observed")
- Lifecycle badge (active/dormant/resolved/recurring)
- "Last active" timestamp
- "First seen" date
- Resident impact score display
- Inline vote grids inside timeline entries
- "Mentioned in meeting minutes or packet" fallback entries
- Document source links on every timeline entry

## Empty Page Handling

If a topic has no upcoming meetings, no summary, no appearances, and no
motions, the page shows:
- Header with name and description
- A single message: "No meeting activity recorded for this topic yet."
- Back to Topics link

## Data Requirements

All data already exists in the database. No new models or fields needed:
- `TopicSummary` — has `content` (markdown), `meeting_id`, `summary_type`
- `TopicAppearance` — has `meeting_id`, `agenda_item_id`, `appeared_at`
- `Motion` — has `description`, `outcome`, linked through agenda items
- `Vote` — has `value`, `member_id`, linked through motions
- `Meeting` — has `starts_at`, `location`, `body_name`

## Controller Changes

The `TopicsController#show` action needs to load:
- `@topic` (existing)
- `@upcoming` — appearances for future meetings
- `@summary` — most recent TopicSummary
- `@recent_activity` — last 3 substantive appearances (past meetings)
- `@decisions` — motions/votes across all appearances

Replace the current `@appearances`, `@status_events`, `@timeline_items` with
the above.

## Scope

This is a view and controller change only. No model changes, no new AI
generation, no new background jobs.
