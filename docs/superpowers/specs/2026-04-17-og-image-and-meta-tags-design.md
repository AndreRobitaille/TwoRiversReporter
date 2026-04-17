# Open Graph Image & Social/SEO Meta Tags

**Status:** Design approved
**Date:** 2026-04-17
**Scope:** Site-wide `og:*`, `twitter:*`, and SEO meta tags. Static site-wide OG image generated from an in-repo ERB template. Per-page title/description overrides with resident-forward copy.

## Goal

Make Two Rivers Matters look credible, specific, and useful in two surfaces:

1. **Social shares** (Facebook, Mastodon, LinkedIn, Discord, Slack, iMessage, SMS) — when a resident shares a link, the preview shows a distinctive image plus a headline that explains what's on the page.
2. **Search results** (Google) — when someone searches "two rivers city council" or a specific topic name, the SERP shows a title and description that immediately identify the site as *Two Rivers, WI city government coverage* and give the scanner enough information to click.

Both surfaces today use the same `<title>` and `<meta name="description">` plus (on one page only) ad-hoc `og:*` tags.

## Audience

Per `docs/AUDIENCE.md`:

- 35+, half over 60. Mobile-heavy scanners, not studiers.
- Skeptical of city leadership. Arrive casually, not habitually.
- Follow topics, not meetings ("Downtown Parking Changes," not "Common Council 2026-02-18").
- Need confidence that clicking leads somewhere useful.
- Plain language, no jargon, no PR voice.
- "Two Rivers" alone is ambiguous (there are Two Rivers in NJ, MN, WA). Local SEO requires explicit "Two Rivers, WI."

The editorial tone established in AUDIENCE.md applies to meta copy as well: factual, matter-of-fact, interested in process and outcomes, not dramatic and not boosterish.

## Visual design — the OG image

**Dimensions:** 1200 × 630 (standard `og:image` size, 1.91:1 aspect ratio).

**Composition:**

- Living Room palette: cream `#faf5eb` background, terra cotta `#c2522a` starburst, teal `#004a59` starburst nucleus and primary text, terra cotta for the second line of the headline.
- Single **upright** starburst (per the design system, starbursts are never canted), centered vertically and positioned to the right, with ~120px of it bleeding off the right edge. Diameter roughly 620px.
- **Headline only.** No brand wordmark, no URL, no tagline, no supporting type.
- Headline text left-aligned, 80px left inset, vertically centered on the canvas:
  - Line 1: `Your City Hall.` — Outfit 900, teal, uppercase, `letter-spacing: -0.03em`, `line-height: 0.88`, ~9.5rem (≈150px) at 1200px width.
  - Line 2: `In Plain English.` — same style, terra cotta.
- No orbit dots, no boomerangs, no secondary motifs.

The headline is the `/about` page H1 and also functions as the site's informal tagline. Using it on the OG image means every social share carries the site's core value proposition.

**Source of truth for the image:** `app/views/og/default.html.erb`, rendered in the Living Room theme with Google Fonts loaded. This ERB is the canonical design — the PNG is a build artifact of this file.

## Meta tag architecture

### Layout-level (`app/views/layouts/application.html.erb`)

Replace the current `<meta name="description">` block with a full OG/Twitter/SEO block driven by `content_for` hooks. Every hook falls back to a sensible default so no page is required to opt in.

```erb
<% page_title = content_for(:title).presence || "Two Rivers, WI City Government — In Plain English" %>
<% page_description = content_for(:description).presence || "A plain-language guide to the Two Rivers, WI city government — what's being decided, what keeps coming back, and what the documents actually say." %>
<% page_url = content_for(:canonical_url).presence || request.original_url %>
<% page_og_type = content_for(:og_type).presence || "website" %>
<% page_og_image = content_for(:og_image).presence || "https://tworiversmatters.com/og-image.png" %>
<% page_og_image_alt = content_for(:og_image_alt).presence || "Two Rivers Matters — Your City Hall. In Plain English." %>

<title><%= page_title %></title>
<meta name="description" content="<%= page_description %>">
<link rel="canonical" href="<%= page_url %>">

<%# Open Graph %>
<meta property="og:site_name" content="Two Rivers Matters">
<meta property="og:type" content="<%= page_og_type %>">
<meta property="og:title" content="<%= page_title %>">
<meta property="og:description" content="<%= page_description %>">
<meta property="og:url" content="<%= page_url %>">
<meta property="og:image" content="<%= page_og_image %>">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="<%= page_og_image_alt %>">

<%# Twitter Card %>
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="<%= page_title %>">
<meta name="twitter:description" content="<%= page_description %>">
<meta name="twitter:image" content="<%= page_og_image %>">
<meta name="twitter:image:alt" content="<%= page_og_image_alt %>">
```

**`content_for` hooks exposed to views:**

| Hook | Purpose | Fallback |
|---|---|---|
| `:title` | Page `<title>` and `og:title` / `twitter:title` | Site-wide title |
| `:description` | `<meta name="description">`, `og:description`, `twitter:description` | Site-wide description |
| `:canonical_url` | `<link rel="canonical">` and `og:url` | `request.original_url` |
| `:og_type` | `og:type` | `"website"` |
| `:og_image` | `og:image` and `twitter:image` | Site-wide PNG |
| `:og_image_alt` | `og:image:alt` and `twitter:image:alt` | Site-wide alt text |

Every page sets `:title`. Pages that want a better description override `:description`. Resource pages (meeting show, topic show) also set `og_type = "article"`.

### Admin layout (`app/views/layouts/admin.html.erb`)

Admin pages should not be shared socially and should discourage indexing. Admin layout adds `<meta name="robots" content="noindex, nofollow">` and skips the OG/Twitter blocks entirely. Admin pages do not need og:image, og:description, etc.

## Per-page titles and descriptions

### Formula

- **Titles**: 30–55 characters. Every public title includes "Two Rivers, WI" or "Two Rivers City Hall" for local SEO disambiguation, except the About page which uses the site tagline. No "— Two Rivers Matters" brand suffix; `og:site_name` carries brand separately.
- **Descriptions**: 100–160 characters. First 120 characters carry the mobile preview. State what's on the page, plainly. No PR verbs ("stay informed," "empowering"), no drama ("fights," "who spoke up"), no internal jargon ("civic transparency," "lifecycle status"). "Plain English" appears only where it's doing identification work, not as filler.

### Static copy

| Page | Title | Description |
|---|---|---|
| **Global fallback** *(used by any page that doesn't override)* | `Two Rivers, WI City Government — In Plain English` | `A plain-language guide to the Two Rivers, WI city government — what's being decided, what keeps coming back, and what the documents actually say.` |
| **Home** `/` | `What's Happening at Two Rivers, WI City Hall` | `What the Two Rivers, WI City Council has been deciding — recent votes, the issues that keep coming back, and what's on the next agenda.` |
| **About** `/about` | `Your City Hall. In Plain English.` | *(existing — unchanged)* `What this site is, where the information comes from, and why it exists. Built by a Two Rivers resident using the city's own public documents.` |
| **Meetings index** `/meetings` | `Two Rivers, WI City Meetings by Date` | `Every Two Rivers, WI city meeting — chronological, with what was on the agenda and what actually got decided.` |
| **Topics index** `/topics` | `Issues Being Tracked in Two Rivers, WI` | `The civic issues in Two Rivers, WI tracked across every city meeting they've appeared at — from first mention through every vote and deferral.` |
| **Committees index** `/committees` | `Two Rivers, WI City Committees` | `The city council, commissions, and committees that govern Two Rivers, WI — who sits on them, what they decide, and how they relate.` |
| **Members index** `/members` | `Two Rivers, WI City Officials & Committee Members` | `The elected officials and appointed members who sit on Two Rivers, WI city boards and committees — attendance, votes, and current appointments.` |

### Dynamic copy

**Meeting show** (`/meetings/:id`)

- Title: `{cleaned body_name}, {short_date} — Two Rivers, WI`
  - `cleaned body_name` strips a trailing ` Meeting` (the meetings/show.html.erb view already does this via `sub(/ Meeting$/, "")`).
  - `short_date` is `starts_at.strftime("%b %-d, %Y")` — e.g. `Apr 14, 2026`.
  - Example: `City Council, Apr 14, 2026 — Two Rivers, WI`
- `og_type`: `"article"`
- Description tiering:
  1. **Has meeting summary** → AI-generated meeting headline via existing `share_og_description(summary)` helper. Unchanged.
  2. **No summary but agenda items parsed** → list the first three agenda-item titles, followed by the count of remaining items, in the form:
     ```
     Two Rivers {cleaned_body_name}, {long_date} — {title_a}, {title_b}, {title_c}, and {N} other items on the agenda.
     ```
     where `long_date` is `starts_at.strftime("%B %-d, %Y")`. Titles are truncated to ~40 chars each; the total description is capped at 160 chars and re-trimmed from the remaining-count tail if needed.
     - If there are exactly 4 items total, list all four without the trailing "and N other items" clause.
     - If there are ≤3 items, list them all.
  3. **No summary, no agenda items** → `Two Rivers {cleaned_body_name} — {long_date}.` Bare and honest.

Tiering lives in a new public helper `MeetingsHelper#meeting_share_description(meeting)`. Internal structure (single method vs a private `agenda_fallback_description` helper) is up to implementation; tests target the public method. The view uses:

```erb
<% content_for(:description) { meeting_share_description(@meeting) } %>
```

**Filtering procedural items:** The agenda-items fallback should skip procedural items (roll call, approval of prior minutes, adjournment) when identifying the "first three" to display. If all items are procedural, fall through to the bare tier 3 format.

**Topic show** (`/topics/:id`)

- Title: `{topic.name} — Two Rivers, WI`
  - Example: `Lead Pipe Replacement — Two Rivers, WI`
- `og_type`: `"article"`
- Description tiering:
  1. **Has briefing with headline** → `@topic.briefing&.headline`. Unchanged — the AI headline is already resident-forward.
  2. **No briefing** → `{topic.name.downcase.capitalize} in Two Rivers, WI — every city meeting where it's come up, every vote, and what's still unresolved.`

A new helper `TopicsHelper#topic_share_description(topic)` returns tier 1 or 2.

**Committee show** (`/committees/:id`)

- Title: `{committee.name} — Two Rivers, WI`
- Description: `{committee.description}` if present (committees have admin-editable descriptions). Falls back to a static line: `The {committee.name} in Two Rivers, WI — members, meetings, and the issues they've taken up.`

**Member show** (`/members/:id`)

- Title: `{member.name} — Two Rivers, WI City Official`
- Description: `{member.name} — committee memberships, meeting attendance, and voting record in Two Rivers, WI city government.`

## Image generation pipeline

### Files

- **`app/views/og/default.html.erb`** — the canonical source of the image design. Standalone HTML document (no layout), inlines Google Fonts, uses the Living Room color tokens, renders the starburst via the existing `shared/_starburst` partial.
- **`lib/tasks/og.rake`** — `bin/rails og:generate` invokes headless Chromium to screenshot the ERB at 1200×630, writes to `public/og-image.png`, then runs `pngquant`/`oxipng` to target under 100 KB.
- **`public/og-image.png`** — the build artifact. Committed to the repo (small, infrequently regenerated). Served directly by Thruster/nginx at `https://tworiversmatters.com/og-image.png`.

### Rake task flow

```
bin/rails og:generate
  ├─ start Rails in a temp server on a free port (or render the ERB to a temp HTML file)
  ├─ invoke `chromium --headless --disable-gpu --hide-scrollbars
  │     --window-size=1200,630 --screenshot=/tmp/og.png <url>`
  ├─ run `pngquant --force --quality=80-95 --output public/og-image.png /tmp/og.png`
  └─ report final file size and warn if > 100 KB
```

Chromium binary path: detect `chromium`, `chromium-browser`, or `google-chrome` on `PATH`, fail with a clear message if none found. Document the dependency in CLAUDE.md's setup notes.

**Regeneration cadence:** manual. Run `bin/rails og:generate` only when the design changes. Not part of CI or deploy.

### File size target

- **Ceiling:** 100 KB.
- **Expected:** 30–80 KB. The design is flat-color with a single SVG starburst and two lines of type — PNG compresses well.
- **Format:** PNG-24 with pngquant dithering to PNG-8 where palette allows.
- Research: WhatsApp truncates aggressively over 300 KB; 100 KB is comfortably under every platform's limit and well within the <300 KB recommended ceiling.

## Files to add / modify / delete

### Add

- `app/views/og/default.html.erb` — OG image ERB source.
- `lib/tasks/og.rake` — `og:generate` task.
- `public/og-image.png` — generated artifact, committed.
- `test/helpers/meetings_helper_test.rb` — tests for `meeting_share_description` tiering. *(existing file — new tests appended.)*
- `test/helpers/topics_helper_test.rb` — tests for `topic_share_description`. *(may or may not exist — add or extend.)*

### Modify

- `app/views/layouts/application.html.erb` — add the full OG/Twitter/SEO meta block, replacing the existing single `<meta name="description">`.
- `app/views/layouts/admin.html.erb` — add `<meta name="robots" content="noindex, nofollow">`.
- `app/views/meetings/show.html.erb` — remove the existing ad-hoc `<meta property="og:*">` block in the `yield :head` section; replace with `content_for(:description)` + `content_for(:og_type)` + updated title.
- `app/views/topics/show.html.erb` — add `content_for(:description)` using `topic_share_description` + `content_for(:og_type)`, update `content_for(:title)` to new format.
- `app/views/home/index.html.erb` — update `content_for(:title)`, add `content_for(:description)`.
- `app/views/meetings/index.html.erb` — update title, add description.
- `app/views/topics/index.html.erb` — update title, add description.
- `app/views/committees/index.html.erb` — update title, add description.
- `app/views/committees/show.html.erb` — update title, add description + `og_type: article`.
- `app/views/members/index.html.erb` — update title, add description.
- `app/views/members/show.html.erb` — update title, add description + `og_type: article`.
- `app/views/pages/about.html.erb` — update `content_for(:title)` to `"Your City Hall. In Plain English."`; existing description stays.
- `app/helpers/meetings_helper.rb` — add `meeting_share_description(meeting)` + `agenda_fallback_description(meeting)`.
- `app/helpers/topics_helper.rb` — add `topic_share_description(topic)`.
- `CLAUDE.md` — note the OG image regeneration command and chromium dependency.

### Delete

Nothing.

### Explicitly not changed

- `share_og_description(summary)` in `meetings_helper.rb` — reused as tier 1 of `meeting_share_description`.
- The AI-generated meeting headlines and topic briefing headlines — they were already written for this audience and function as tier 1 description content on their own.

## Testing

- **Helper unit tests** for `meeting_share_description` covering: summary present, no summary but 3+ agenda items, no summary and 4 items, no summary and ≤3 items, no summary and no agenda items, agenda with only procedural items.
- **Helper unit tests** for `topic_share_description` covering: briefing present with headline, briefing present without headline, no briefing.
- **View render tests** confirming each layout renders the expected `og:*` tags for one representative page per type (home, about, meeting show, topic show).
- **Manual validation** using the Facebook Sharing Debugger, Twitter Card Validator, and LinkedIn Post Inspector against production (`https://tworiversmatters.com/`) after deploy. These are manual steps, not automated tests.

## SEO considerations

- **Description freshness:** Descriptions are cached by search engines between crawls. For a small civic site, that may mean weekly or longer between recrawls. All index-page descriptions (home, meetings, topics, committees, members) are written to remain accurate across that window — no "recent: X, Y, Z" content that will stale out. Dynamic descriptions only appear on per-resource pages (a specific meeting or topic), where the content is stable for that URL.
- **Canonical URLs:** Every page now emits `<link rel="canonical">` pointing to `request.original_url`. Pages with query parameters that shouldn't be canonicalized (none currently exist publicly) can override via `content_for(:canonical_url)`.
- **Robots:** Public pages use the implicit default (indexable). Admin pages emit `noindex, nofollow`.
- **Social site verification:** Not adding `fb:app_id`, `twitter:site`, or `linkedin:owner` in this pass. Those require us to have accounts on each platform, which we do not. Revisit if and when we create official social accounts.

## Non-goals / out of scope

- **Per-page dynamic OG images** — not now. A single site-wide image is simpler, cheaper, and perfectly adequate for a site whose share traffic is low. If share traffic grows and meeting/topic-specific previews would drive clicks, a future project can add a render pipeline (e.g. ERB → headless Chromium per request with caching).
- **Sitemap and robots.txt updates** — out of scope. There's an existing `public/robots.txt` that doesn't need to change for this work.
- **Structured data / JSON-LD** — out of scope. Could be added later for richer search-engine understanding (e.g. `GovernmentOrganization`, `Event` for meetings), but not needed to ship the social previews.
- **Preview-debug admin tooling** — out of scope. Manual validation via external tools is sufficient.

## Rollout plan

1. Land the changes on master.
2. Run `bin/rails og:generate` locally, commit the PNG.
3. `bin/kamal deploy`.
4. Smoke-test the OG tags with:
   - `curl -s https://tworiversmatters.com/ | grep -E '(og:|twitter:|description)'`
   - Facebook Sharing Debugger (scrape `/`, `/about`, a meeting page, a topic page — confirm the image loads, titles and descriptions look right).
   - Twitter Card Validator (same URLs).
5. Update CLAUDE.md with the OG regeneration workflow.

No database changes, no job changes, no risk of data corruption. Rollback is `git revert` of the commits.
