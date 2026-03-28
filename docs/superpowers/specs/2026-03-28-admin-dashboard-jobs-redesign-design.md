# Admin Dashboard & Jobs Page Redesign

## Summary

Redesign the `/admin` dashboard and `/admin/jobs` pages with an Atomic-era (1950s-60s post-war optimism) visual identity. The dashboard becomes a "Mission Control" command center surfacing status and actionable items. The jobs page becomes a pipeline-oriented monitoring view for watching batches process through.

## Design Language: Warm Atomic

### Color Palette (5 colors)

| Role | Color | Hex |
|------|-------|-----|
| Primary (headings, links, borders) | Deep teal | `#004a59` |
| Action/alert (section labels, attention) | Terra cotta | `#c2522a` |
| Warning/active | Amber | `#d4872a` |
| System/security category | Plum | `#6b4c8a` |
| Success | Forest green | `#2a8a4a` |

Background: `#faf5eb` (warm cream). Surface: `#fff`. Borders: `#e0ddd7`, `#d4c9b8`.

### Typography

| Role | Font | Weight | Style |
|------|------|--------|-------|
| Display headings, counts, nav labels | Anybody | 700-900 | Uppercase, tight tracking |
| Body text, buttons | Space Grotesk | 400-600 | Normal |
| Labels, metadata, timestamps | DM Mono | 400-500 | Uppercase, wide tracking |

All three are Google Fonts. Load via `@import` or `<link>` in the admin layout.

### Graphic Motifs

- **Starburst SVG** — 12-point star in terra cotta with teal center dot. Used in the page header next to "Mission Control" / "Job Queue".
- **Atom-orbit section markers** — 16px circle with 2px terra cotta border and filled center dot. Used as bullet for every section label.
- **Diamond divider** — Gradient line (terra cotta -> amber -> teal) with a rotated-45deg terra cotta diamond. Used once below the page header.
- **Decorative orbital rings** — Large faint circles (`rgba(0,74,89,0.06)`) positioned in the top-right corner as background decoration.

### Layout Patterns

- **No full-width rows with far-apart info and actions.** Information and its action must be within comfortable mouse-travel distance.
- **Cards for grouped/actionable items** — compact, stacked vertically within the card, equal-height in grids.
- **Teal top/bottom border** on vertical list sections (workers, status entries).
- **Section labels** use atom marker + uppercase Anybody text + trailing 1px line.

## Dashboard (`/admin`)

### Page Title

"Mission Control" with starburst SVG. Subtitle: "Two Rivers Reporter - Admin Dashboard" in DM Mono.

### Layout: Two Columns

Left column (wider): **Needs Attention** section.
Right column (200px): **Status** section.

#### Needs Attention (left)

Clickable rows, each showing:
- Diamond icon (amber, rotated 45deg)
- Bold count (Anybody font, terra cotta)
- Plain-language description
- Arrow (teal)

Each row is a link to the relevant admin page. The entire row is clickable.

Items to surface (query from controller):
- Topics with `review_status: :needs_review` count -> links to `/admin/topics?status=needs_review`
- `SolidQueue::FailedExecution.count` > 0 -> links to `/admin/jobs`
- Meetings with documents but no summary -> links to `/admin/summaries`
- Topics with `status: :proposed` (auto-triage pending) -> links to `/admin/topics?status=proposed`

When nothing needs attention, show a single row: "All clear. Nothing needs your attention."

#### Status (right)

Vertical list entries with colored dots:
- Worker status (green if heartbeat < 60s, red otherwise)
- Scraper status (derived from whether any scraper job is running/scheduled)
- Queue count (amber if > 0, green if 0)
- Failed count (red if > 0, green if 0)

Each entry: dot + label + right-aligned value in DM Mono.

### Navigate Section

3-column grid of nav items. Each item has:
- Name in Anybody font (teal, uppercase)
- Hint line showing a relevant count or status

Color-coded bottom borders by category:
- **Content** (teal): Topics, Committees, Members, Knowledge, Blocklist
- **Operations** (amber): Job Queue, Summaries
- **System** (plum): Users, Security

### Footer

Single row with DM Mono links: Change Password, Recovery Codes, Sign Out.

### Controller Changes

`Admin::DashboardController#show` needs to query:
- `Topic.where(review_status: :needs_review).count`
- `Topic.where(status: :proposed).count`
- `SolidQueue::FailedExecution.count`
- Meetings needing summaries (meetings with summarizable docs but no MeetingSummary)
- Worker alive status (same logic as jobs controller)
- Queue counts (ready + scheduled + claimed)
- Navigation hint counts: active committees, total members, knowledge sources, blocklist entries, admin users

## Jobs Page (`/admin/jobs`)

### Page Title

"Job Queue" with starburst SVG. Back link: "< Mission Control". Subtitle: "Background tasks running behind the scenes".

### Header Actions

Two buttons in the header row (right-aligned):
- "Clear Finished" (neutral style)
- "Retry All Failed" (danger style, only shown when failed > 0)

### Layout: Workers + Pipeline (two columns)

Left column (200px): **Workers** — vertical list with green dots, showing "active" or "stale".

Right column: **Pipeline** — 4 stages in a horizontal flow:
1. Scheduled ("waiting for their time")
2. Ready ("next up to run")
3. Running ("working now") — amber count
4. Failed ("need your attention") — red count, red border, pink background

Each stage shows a large count in Anybody font + label in DM Mono + italic description.
Triangle arrows (`▸`) between stages.

### What's in the Queue

Vertical list rows showing pending jobs grouped by type. Each row:
- Plain-language description (not class name)
- Mini bar chart (teal-to-amber gradient, proportional width)
- Count

**Job class to plain language mapping** (hardcoded in a helper):

| Class | Description |
|-------|-------------|
| `ExtractTopicsJob` | Finding topics in meetings |
| `SummarizeMeetingJob` | Writing meeting summaries |
| `Documents::DownloadJob` | Downloading meeting documents |
| `Documents::AnalyzePdfJob` | Analyzing PDF documents |
| `GenerateTopicBriefingJob` | Updating topic headlines |
| `Scrapers::ParseAgendaJob` | Parsing meeting agendas |
| `Scrapers::DiscoverMeetingsJob` | Discovering new meetings |
| `ExtractVotesJob` | Recording votes from minutes |
| `ExtractCommitteeMembersJob` | Identifying committee members |
| `Topics::UpdateContinuityJob` | Updating topic lifecycle |
| `Topics::GenerateDescriptionJob` | Writing topic descriptions |
| `IngestKnowledgeSourceJob` | Indexing knowledge sources |

Fallback for unknown classes: humanize the class name.

### Failed — Needs Attention

**Grouped by error pattern**, not listed individually. Grouping key: job class + error message pattern (first line, with variable parts like IDs stripped).

Each group renders as a **compact card** (not a full-width row):
- Header: diamond icon + "Topic extraction failed (12 jobs)" or "Document download failed" (single)
- Subject line: meaningful noun(s). For grouped: "Council Mar 24, Plan Commission Mar 18, and 10 others". For single: "Parks Committee agenda (Apr 2)".
- Error message in terra cotta
- **Guidance line** in plum italic — hardcoded per error pattern
- Footer (pinned to card bottom with separator line): time range on left, action buttons on right

**Error-to-guidance mapping** (hardcoded in a helper):

| Error Pattern | Guidance |
|---------------|----------|
| `rate limit` | Usually resolves on its own. Safe to retry in a few minutes. |
| `timeout`, `connection` | Temporary network issue. Safe to retry now. |
| `no extracted text`, `no text found` | The source documents may need re-downloading. Check the meeting records first. |
| `JSON`, `parse error`, `unexpected response` | May indicate a prompt issue. Review the error details before retrying. |
| `not found`, `404` | The source document may have been removed from the city website. |
| (default) | Check the error details and retry if the issue seems temporary. |

Cards use `grid` with `align-items: stretch` so footers align across cards of different heights.

Action buttons: "Retry All 12" / "Discard All" for groups. "Retry" / "Discard" for singles.

**Subject resolution** — the controller needs to resolve job arguments to meaningful names:

| Job Class | Argument | Resolution |
|-----------|----------|------------|
| `ExtractTopicsJob` | `meeting_id` | `meeting.body_name + meeting.date` |
| `SummarizeMeetingJob` | `meeting_id` | `meeting.body_name + meeting.date` |
| `Documents::DownloadJob` | `meeting_document_id` | `document.title` or `meeting.body_name + " " + document.document_type` |
| `Documents::AnalyzePdfJob` | `meeting_document_id` | same as above |
| `GenerateTopicBriefingJob` | `topic_id` | `topic.name` |
| `Topics::GenerateDescriptionJob` | `topic_id` | `topic.name` |
| `ExtractVotesJob` | `meeting_id` | `meeting.body_name + meeting.date` |
| `ExtractCommitteeMembersJob` | `meeting_id` | `meeting.body_name + meeting.date` |
| `Scrapers::*` | varies | `meeting.body_name + meeting.date` or URL |

Fallback: show truncated arguments string if resolution fails.

**Grouping key**: `[job.class_name, normalize_error(error_message)]` where `normalize_error` strips variable content (IDs, timestamps, specific values) to produce a stable pattern string. For example, "Couldn't find Meeting with id=142" becomes "Couldn't find Meeting with id=*".

### Recently Finished

Vertical list rows:
- Green atom-dot (filled circle with center dot)
- Plain-language description with context (e.g., "Summarized Council Meeting — Mar 24")
- Right-aligned: time ago + duration in DM Mono

Same subject resolution as failed jobs. Limited to 50 most recent.

### Empty State

When no jobs exist: "No jobs in the queue. Tasks will appear here when meetings are scraped or summaries are regenerated."

## CSS Architecture

All new styles go in a new admin-specific stylesheet: `app/assets/stylesheets/admin.css`. This keeps the Atomic design language separate from the public site's civic design.

The admin stylesheet will be loaded conditionally — only on admin pages. This requires either:
- An admin-specific layout (`app/views/layouts/admin.html.erb`) that includes the admin stylesheet, OR
- A `content_for :head` block in admin views

**Recommendation: Create `app/views/layouts/admin.html.erb`** — this also lets us swap the public site header/footer for a simpler admin chrome (just the starburst + "Mission Control" branding, no public nav).

The public site's `application.css` utility classes (`.btn`, `.badge`, `.flex`, etc.) remain available and can be used alongside the new admin classes.

## Admin Layout

Create `app/views/layouts/admin.html.erb`:
- Same `<head>` as application layout (csrf, importmap, etc.)
- Loads `admin.css` in addition to `application.css`
- Google Fonts link for Anybody, Space Grotesk, DM Mono
- No public site header/footer — admin pages are a separate experience
- Simple body wrapper with warm cream background
- Flash message rendering (notice/alert)

## Files to Create/Modify

### New Files
- `app/assets/stylesheets/admin.css` — all Atomic-era admin styles
- `app/views/layouts/admin.html.erb` — admin layout with fonts + admin CSS
- `app/helpers/admin/jobs_helper.rb` — job class descriptions, error guidance, subject resolution

### Modified Files
- `app/views/admin/dashboard/show.html.erb` — complete rewrite
- `app/views/admin/jobs/show.html.erb` — complete rewrite
- `app/controllers/admin/dashboard_controller.rb` — add queries for status/attention items
- `app/controllers/admin/jobs_controller.rb` — add failed job grouping, subject resolution
- `app/controllers/admin/base_controller.rb` — set `layout "admin"`

## Testing

- Existing admin tests should continue to pass (controller tests check responses, not markup).
- No new test files needed for the redesign itself — it's purely presentational with data queries that can be verified by inspecting the pages.
- Manually verify: dashboard with zero items needing attention, dashboard with items in every category, jobs page with zero jobs, jobs page with many grouped failures, jobs page with mixed failure types.
