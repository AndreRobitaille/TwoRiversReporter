# Meeting Share Button — Design Spec

**Date:** 2026-04-13
**Status:** Approved

## Overview

Add a share button to the meeting detail page that lets residents share meeting information on Facebook or copy a formatted summary to their clipboard. The share text adapts to meeting tense — upcoming meetings describe what's on the agenda; past meetings describe what happened.

## Share Button (UI)

### Placement

Inline with the existing document links row (`.meeting-article-docs`), visually distinct from the source links. A vertical separator (1px line) divides the document links (Minutes, Agenda, City Website) from the share action. The share button uses a terra-cotta accent border to differentiate "share this" from "read this".

### Visual Treatment

- Same size and shape as existing `.meeting-doc-link` pills
- Terra-cotta border color (`--color-terra-cotta`) instead of the default border
- Terra-cotta text color
- Share icon SVG (external-link or share arrow)
- Label: "SHARE"
- DM Mono font, uppercase, same as other doc links

### Dropdown

Clicking the share button toggles a small dropdown popover anchored below/right of the button. Two items:

1. **Share on Facebook** — opens Facebook Share Dialog in a popup window
2. **Copy summary** — copies formatted text to clipboard, button text changes to "Copied!" for 2 seconds

Dropdown is positioned absolutely relative to a wrapper `div`. Closes on outside click or Escape key. Pure CSS + Stimulus — no external dependencies.

## Share Text Format

Assembled server-side by `MeetingsHelper#share_text(meeting, summary)`. No AI calls — uses existing `generation_data` from the meeting's summary.

### Structure

```
[body_name sans " Meeting" suffix] — [Month Day, Year], [Time]

[headline paragraph from generation_data]

[section header]:
 - [item with optional context]
 - [item]
 ...

Full details at Two Rivers Matters:
https://tworiversmatters.com/meetings/[id]
```

### Tense Detection

Based on `meeting.starts_at` vs `Time.current`:

- **Upcoming meetings** — section header: "On the agenda:". Bullets pulled from `generation_data["item_details"]` titles. High-impact items (those that also appear in `highlights`) get one sentence of context appended.
- **Past meetings** — section header: "Key decisions:". Bullets pulled from `generation_data["highlights"]`, which include vote outcomes.

### Bullet Rules

- Max 5 bullets to keep the post scannable
- Items that appear in `highlights` get context (the highlight text)
- Other items are clean one-liners (just the `agenda_item_title`, cleaned up)
- For past meetings: append vote result if present (e.g., "approved 5-2")

### Fallback Tiers

1. **Has `generation_data`** — full formatted text as described above
2. **Has agenda items but no summary** — meeting name + date + agenda item titles as bullets + link
3. **Nothing** — meeting name + date + link only

### Tone

- Professional, no emoji
- Plain text (no markdown — Facebook doesn't render it)
- Line breaks and ` - ` bullets for structure
- Branded footer: "Full details at Two Rivers Matters:"

## Facebook Share Dialog

URL pattern: `https://www.facebook.com/sharer/sharer.php?u={encoded_meeting_url}`

- Opens as a centered popup window (600x400px)
- Facebook scrapes the target page's Open Graph meta tags to build the link preview card
- No Facebook App ID required for the basic sharer endpoint
- Meeting URL uses the production domain: `https://tworiversmatters.com/meetings/{id}`

## Open Graph Meta Tags

Added to the meeting show page `<head>` via `content_for(:head)`:

| Tag | Value |
|-----|-------|
| `og:title` | "[body_name] — [formatted date]" |
| `og:description` | `generation_data["headline"]` truncated to 200 chars. Falls back to "Meeting details and AI-generated summary." |
| `og:url` | Canonical meeting URL (`https://tworiversmatters.com/meetings/{id}`) |
| `og:type` | `article` |
| `og:site_name` | "Two Rivers Matters" |

No `og:image` — Facebook will use a default placeholder. Share card image is a future feature.

## Stimulus Controller

`share_controller.js` registered on a wrapper element around the share button + dropdown.

### Targets

- `dropdown` — the dropdown element
- `copyButton` — the copy summary button (for text swap feedback)

### Values

- `text` — the share text string (set from server-rendered `data-share-text-value`)
- `url` — the meeting's canonical URL (for Facebook share)

### Actions

- `toggle` — toggles dropdown visibility
- `facebook` — opens Facebook sharer popup (`window.open`, centered 600x400)
- `copy` — copies `textValue` to clipboard via `navigator.clipboard.writeText()`, swaps button text to "Copied!" for 2 seconds
- `close` — closes dropdown (bound to `click@window` and `keydown.esc@window`)

## File Changes

| File | Change |
|------|--------|
| `app/views/meetings/show.html.erb` | Add share button + dropdown markup after City Website link, add OG meta tags via `content_for(:head)` |
| `app/helpers/meetings_helper.rb` | Add `share_text(meeting, summary)` and `share_og_description(summary)` methods |
| `app/javascript/controllers/share_controller.js` | New Stimulus controller |
| `app/assets/stylesheets/application.css` | Share button variant styles, dropdown styles |

## Not in Scope

- Other share targets (Twitter/X, email, Nextdoor) — same pattern, easy to add later
- Share card / OG image generation — future feature
- Share analytics or click tracking
- Topic page sharing — same pattern, separate ticket
- AI-generated share text — we use what's already in `generation_data`
