# About Page — Design Spec

**Date:** 2026-04-12
**Status:** Draft

------------------------------------------------------------------------

## Purpose

A resident arrives from a Facebook post — maybe outraged, maybe just
curious. They've never seen this site before. At some point they wonder:
What is this? Who made it? What's the angle? Where does the information
come from?

The About page answers those questions. It's structured as an inverted
pyramid: the top answers the 5-second visitor, the middle handles the
skeptic, and the bottom satisfies the person trying to disprove the
site's legitimacy.

------------------------------------------------------------------------

## Audience

The reader described in `docs/AUDIENCE.md`. Key constraints:

- Mobile-heavy, phone-first
- Scanners — they want the gist fast
- Skeptical of institutions and of this site until proven otherwise
- Non-technical — terms like "topics," "pipeline," "citations," and
  "importance scoring" mean nothing to them
- In a tight social-capital community — the page should not read as a
  personal profile or political statement

------------------------------------------------------------------------

## Language Rules

The page must be written in resident terms throughout. The "Under the
Hood" section can introduce architectural concepts but must always lead
with the plain version.

| Internal term | Resident-facing language |
|---|---|
| Topic | "issue" or "thing the city is working on" |
| Impact/importance score | "how it decides what to show you first" |
| Active/dormant/resolved | "still being discussed" / "hasn't come up in a while" / "got a final vote" |
| Factual record | "what actually happened" |
| Institutional framing | "how the city describes it" |
| Civic sentiment | "what residents seem to care about" |
| Pipeline / ingestion | "checks for new documents every night" |
| Citations | "links back to the original document" |
| Extraction | "reads and pulls out the key points" |
| Topic extraction | never mention |
| Scraping | never mention — say "checks the city website" |

------------------------------------------------------------------------

## Route & Navigation

- **Route:** `GET /about` → `PagesController#about`
- **Controller:** New `PagesController` with a single `about` action.
  No database queries. Static content rendered from the view template.
- **Nav:** Added to site header as the rightmost link (after "City
  Officials"). Also added to footer links.
- **Sitemap:** Add `/about` to `SitemapsController`.

------------------------------------------------------------------------

## Layout

Single `.topic-article` reading column (38rem max-width, centered),
same pattern as the topic show page. Static anchor bar below the header.
Diamond dividers between major zones.

**Heavy use of Atomic-era design vocabulary:** starbursts, boomerangs,
atom markers, diamond dividers — the full Living Room motif set. This
page has more room for decorative elements than data-driven pages.

------------------------------------------------------------------------

## Page Structure

### Zone 1: The Hook

Full-width header area above the anchor bar. This is the only thing a
5-second visitor sees.

- **Eyebrow:** DM Mono uppercase, terra cotta — "ABOUT THIS SITE"
- **Title:** Large Outfit uppercase — "Not a City Website. Not the
  News." (or similar — blunt, kills the two biggest misconceptions)
- **Subtitle:** One sentence, Space Grotesk — "A Two Rivers resident
  built this to help you follow what's happening at city hall — using
  nothing but the city's own public documents."
- **Decorative:** Starburst SVG as a watermark or flanking element.
  This is the most prominent decorative moment on the page.

### Anchor Bar

Static (NOT sticky). Sits directly below the hook. Styled with DM Mono
uppercase, wide letter-spacing — the data/metadata treatment used for
timestamps and chips elsewhere. Terra cotta underline on the active or
hovered link. Atom marker SVGs as separators between items.

Links:
- **How It Works** | **Your Questions** | **The Bias** | **Under the
  Hood**

On mobile, wraps to two lines. No hamburger, no collapse — just let it
wrap.

### Zone 2: How It Works

Section header: atom marker + "HOW IT WORKS" + gradient line (reuses
`.home-section-header` pattern from homepage).

A vertical step diagram — four cards, each with a teal left border,
numbered. Not a paragraph of text.

**Step 1 — The city posts documents.**
Agendas, meeting packets, and minutes. Wisconsin's Open Meetings Law
requires them to be public. That's the only source this site uses.
*(Link: Wis. Stats. §19.84)*

**Step 2 — This site checks every night.**
New meeting dates, new documents. Copies are saved here so nothing
disappears even if the city moves or removes the originals.

**Step 3 — AI reads them and writes summaries.**
In plain language, not government-speak. Every claim links back to the
original document so you can read it yourself.

**Step 4 — Issues are tracked across meetings.**
Instead of organizing by meeting date, the site follows things like
"downtown parking" or "lead pipe replacement" across months of meetings
so you don't have to dig through a dozen agendas.

Boomerang SVG as a decorative element between or beside steps.

### Diamond Divider

### Zone 3: Your Questions, Answered

Section header: atom marker + "YOUR QUESTIONS" + gradient line.

Each Q&A is a distinct block with a bold question header and the answer
below. Generous spacing between entries.

**"Who's behind this?"**
One resident, working independently. Not connected to city hall, not
funded by anyone, not affiliated with any political group or candidate.
The site costs money to run — that comes out of pocket. No ads, no
sponsors.

**"Who's paying for this?"**
Hosting and AI processing costs — paid by the person who built it. No
revenue, no grants, no city funding. If that ever changes, it'll be
stated here.

**"What's the bias?"**
This site is not neutral and doesn't pretend to be. It's built with a
point of view: residents deserve to understand what's happening at city
hall, and the way the city presents information isn't always the full
picture.

The AI is specifically instructed to question how decisions are framed —
not to assume the city's description of something is the whole story.
It's also told never to accuse anyone of bad intentions or bad faith.
Decisions and processes get questioned. People don't.

**"Can I trust what the AI writes?"**
The AI reads the same documents you could find on the city's website.
It's told to separate what actually happened (votes, motions, dollar
amounts) from how the city describes it. Every summary links back to
the source so you can read the original yourself. If something looks
wrong, check it — that's the whole point.

**"What doesn't this cover?"**
Routine business that doesn't affect your life — license renewals,
proclamations, approving last month's minutes, things like that. The
site focuses on what hits your taxes, your neighborhood, your streets,
your water. If nobody showed up to talk about it and the vote was
unanimous on something routine, it probably doesn't appear here.

**"Who decides what shows up on the front page?"**
Not a person. The system looks at signals: Did people show up to
comment? Was the vote close? Does it affect property taxes or zoning?
Has it come up at multiple meetings over time? Issues with more of
those signals get featured. Issues without them are still on the site —
just not on the front page.

### Diamond Divider

### Zone 4: Under the Hood

Section header: atom marker + "UNDER THE HOOD" + gradient line.

Visual tone shifts — cool-toned background tint for this zone (similar
to the transcript banner treatment). This is where the Silo aesthetic
bleeds in slightly. The audience here is the person who scrolled past
everything above looking for the flaw. Language is more direct and
specific, but still leads with the plain version of each concept.

**How the AI is instructed**

The AI that writes summaries follows written rules about how to handle
city documents. Three categories are kept separate:

- **What actually happened** — votes, motions, dollar amounts, dates.
  These come straight from the official record and must be traceable to
  a specific document.
- **How the city describes it** — staff summaries, agenda titles, the
  language in meeting packets. The AI treats this as the city's
  perspective, not as neutral truth. When the city's description doesn't
  match the outcome or the observable impact, the AI is told to note
  that.
- **What residents seem to care about** — based on who shows up to
  comment, what keeps coming back meeting after meeting, and how divided
  the votes are. The AI is told to present this as observation, never as
  established fact.

The person who built this site also wrote a detailed description of who
Two Rivers residents are — what they care about, what's routine, what
local governance quirks matter (like how height-and-area exceptions get
used, or why CDA agendas aren't always substantive). Those instructions
shape how every summary is written.

**How issues are tracked across meetings**

When something like "Lead Service Line Replacement" shows up on an
agenda in January, then again in a committee meeting in March, then
gets voted on by the Council in June — those are all automatically
connected. The system notices when an issue is still being discussed,
when it hasn't come up in a while, and when it got a final vote. That's
how the site can tell you something has been deferred three times or
that a topic reappears every budget cycle.

**What gets filtered out**

The summaries skip procedural business that every meeting has:
adjournment motions, approving last meeting's minutes, roll call for
remote participation, consent agenda items that are truly routine. One
exception: when the council goes into closed session, the motion to
close IS included — Wisconsin law (§19.85) requires transparency about
what gets discussed behind closed doors, and residents should see that.

**How it decides what to show you first**

The front page features issues based on automated signals, not human
judgment. The system weighs:

- Whether residents showed up to speak about it (strongest signal)
- Whether the vote was close or split
- Whether it affects property taxes, zoning, or infrastructure
- Whether it's come up across multiple meetings or committees
- Whether there have been repeated deferrals or unresolved questions

No one hand-picks what goes on the front page. An issue about sidewalk
repair and an issue about a $2M TIF district go through the same
scoring — the TIF district scores higher because it triggers more of
those signals.

**The source documents**

Every meeting page on this site has a "Documents" section with the
original PDFs from the city. The city is required by Wisconsin's Open
Meetings Law to make these available to the public. This site saves
copies because government websites sometimes reorganize, move pages, or
remove old documents.

Relevant Wisconsin statutes:
- [Chapter 19, Subchapter V](https://docs.legis.wisconsin.gov/statutes/statutes/19/v) —
  Open Meetings Law (full text)
- [§19.84](https://docs.legis.wisconsin.gov/statutes/statutes/19/v/84) —
  Public notice requirements for meetings
- [§19.88(3)](https://docs.legis.wisconsin.gov/statutes/statutes/19/v/88) —
  Minutes must be available for public inspection

------------------------------------------------------------------------

## Visual Design Details

### Atomic-Era Motifs (Heavy Use)

This page should be the most decorated public page on the site. It has
no data constraints — every other page needs to stay out of the way of
meeting data or topic timelines. This page is pure editorial, so the
Atomic vocabulary can breathe.

- **Starburst:** Large, low-opacity, positioned behind the hook title
  text via CSS (absolute positioning within the header). Not inline
  beside the title. Sets the visual tone immediately.
- **Boomerangs:** Beside or between the pipeline steps in Zone 2.
  Decorative, not structural.
- **Atom markers:** In every section header (existing pattern) and as
  separators in the anchor bar.
- **Diamond dividers:** Between zones (existing pattern).
- **Radar sweep:** Optional — could appear in the "Under the Hood"
  zone to signal the tonal shift to the Silo aesthetic.

### Typography

- **Hook title:** Outfit, uppercase, `clamp(2rem, 5vw, 3rem)`, teal.
  Same treatment as `.topic-article-title`.
- **Anchor bar:** DM Mono, uppercase, wide tracking. Same treatment as
  metadata chips.
- **Section headers:** Reuse `.home-section-header` (atom marker +
  label + gradient line).
- **FAQ questions:** Space Grotesk, bold, 1.1rem. Stand out as scan
  targets.
- **FAQ answers:** Space Grotesk, regular weight, comfortable reading
  size.
- **Under the Hood sub-headers:** Outfit, uppercase, smaller than
  section headers. Terra cotta color.

### Color

- Zones 1-3: Living Room theme (warm cream `#faf5eb` background)
- Zone 4: Subtle shift toward cool tones — light concrete-tinted
  background (like `#f2f5f5` or similar). Not full Silo theme, just a
  hint that the register has changed.
- All colors via CSS custom properties, no hardcoded hex.

### Responsive

- Anchor bar wraps naturally on small screens. No collapse/hamburger.
- Pipeline steps stack vertically (they already are vertical).
- FAQ entries are full-width blocks — no layout changes needed.
- Zone 4 background tint spans full width on all screens.

------------------------------------------------------------------------

## What This Page Does NOT Include

- **No contact form or email.** Not yet. Can be added later.
- **No user accounts or login references.**
- **No specific names of city officials or council members.**
- **No mention of scraping, crawling, or any technical acquisition
  method.** The site "checks for new documents." That's it.
- **No mention of specific AI models or vendors.** Just "AI." Residents
  don't care if it's GPT or Claude — they care if they can trust the
  output.
- **No code snippets, API references, or developer documentation.**
  This is a resident-facing page.

------------------------------------------------------------------------

## Implementation Notes

- **Static content.** No database queries, no instance variables. Pure
  ERB template with hardcoded content.
- **New controller.** `PagesController` with `about` action. Keeps the
  door open for future static pages (privacy policy, etc.) without
  polluting existing controllers.
- **CSS.** New `about.css` stylesheet for page-specific styles (anchor
  bar, pipeline steps, Zone 4 background tint). Reuse existing classes
  (`.topic-article`, `.home-section-header`, `.diamond-divider`) where
  possible.
- **No JavaScript.** Anchor links use native `id` + `href="#id"`. No
  smooth scroll JS — let the browser handle it.
- **Decorative SVGs** via existing shared partials (`_starburst`,
  `_boomerang`, `_atom_marker`, `_diamond_divider`, `_radar_sweep`).
