# Homepage & Topics Index — Visual Affordance & Clarity Pass

## Problem

Both pages have jargon that alienates residents, interactive elements that don't look tappable (especially on mobile), and information hierarchy that serves staffers more than curious neighbors. A resident visiting 1-2x/month on their phone can't quickly tell what's clickable, what to pay attention to, or what the government jargon means.

## Audience

Non-technical Two Rivers residents. Visit rarely. On phones. Don't know what "packet", "agenda items", or "body" mean. Want: "What's going on?" and "Should I care?" and "What can I do?"

## Design Principle

Same as issue #63: affordances visible at rest, on first glance, on a phone. Plus: no government jargon in resident-facing labels.

---

## Topics Index (`/topics`)

### Topic cards (`_topic_card.html.erb`)

- **Add "View topic →" button** — `<span class="btn btn--secondary btn--sm">View topic →</span>` at bottom of card body. Explicit tap target matching the pattern from topic show page.
- **Move inline style to CSS** — remove `style="text-decoration: none; color: inherit;"` from the link_to; the `.card--clickable` class handles this.
- **Promote description** — change from `text-sm text-secondary` to just `text-secondary` (normal font size). The description does the explanatory work; the topic name alone is often opaque.
- **Demote lifecycle badge** — move from card header (competing with title) into the metadata row at the bottom, next to "Updated X ago".
- **Dejargon "agenda items"** — change "N agenda items" to "Discussed N times". Shorter, clearer, no jargon.
- **Rename signal badges** in `topics_helper.rb`:
  - "Deferral Observed" → "Delayed"
  - "Moved Bodies" → "Moved to new committee"
  - "Disappeared" → "No longer on agenda"

### Page copy

- Subtitle: "Topics currently under discussion in Two Rivers" → "What Two Rivers city government is working on"
- Hero subtitle: "High-impact topics with recent activity." → "The biggest issues right now"

### Archive link

- Promote from `text-secondary text-sm` fine print to `btn btn--secondary` button treatment. Keep the explanatory text above it.

---

## Homepage (`/`)

### Topic headline items (`_topic_headline_item.html.erb`)

- **Style topic name as a visible link** — accent color + underline on the topic name. The standard web affordance for "this is clickable."
- **Add arrow** — append `→` after the topic name to reinforce tappability.

### Card footers

- **Upgrade "All topics →"** from `text-sm` link to `btn btn--secondary btn--sm`.

### Empty state for topic cards

- When both Coming Up and What Happened are empty, show: "No hot topics right now. Check the meetings below to see what's scheduled."

### Meeting table — single status badge

Replace the multi-badge "Info" column with a single resident-friendly status indicator.

**New helper: `meeting_status_badge(meeting)`**

Maps `meeting.document_status` + time context to one badge:

| document_status | Upcoming meeting | Past meeting (3hr+) |
|---|---|---|
| `:none` | — (no badge) | Awaiting minutes (warning) |
| `:agenda` | Agenda posted (info) | Awaiting minutes (warning) |
| `:packet` | Documents available (info) | Awaiting minutes (warning) |
| `:minutes` | n/a | Minutes available (success) |

If `meeting.meeting_summaries.any?`, add: "Summary" badge (success).

The status badge replaces the entire "Info" column. It goes next to the date instead.

### Meeting table — dejargon

- Column header "Body" → "Committee"
- Remove "Info" column (replaced by status badge near date)
- Column order: **Date + Status** | **Committee** | **Topics** | (View button)

### Meeting table — mobile

- CSS media query hides "Topics" column below 768px. Meeting detail page has full topic info.
- This leaves Date+Status, Committee, and View on mobile — three clean columns.

### 3-hour meeting buffer

- Add `MEETING_BUFFER = 3.hours` to `HomeController`
- Change the upcoming/recent boundary from `Time.current` to `Time.current - MEETING_BUFFER`
- A 6pm meeting stays in "Upcoming" until ~9pm

---

## Scope

- View changes: `_topic_card.html.erb`, `_topic_headline_item.html.erb`, `_meeting_row.html.erb`, `_meeting_week_group.html.erb`, `home/index.html.erb`, `topics/index.html.erb`
- Helper changes: `topics_helper.rb` (signal badge labels), new `meetings_helper.rb` or `home_helper.rb` (meeting status badge)
- Controller change: `home_controller.rb` (3-hour buffer constant, query boundary adjustment)
- CSS changes: `application.css` (mobile column hiding, topic headline link styling, card--clickable text reset)
- No model changes. No new features. No new routes.
