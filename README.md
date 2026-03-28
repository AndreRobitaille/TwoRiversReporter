# Two Rivers Reporter

Civic transparency site for Two Rivers, WI. Ingests official city meeting documents (PDFs, HTML), preserves them as authoritative records, and produces citation-backed AI summaries for residents.

**Topics** (persistent civic concerns like "Downtown TIF District" or "Lead Service Line Replacement") are the primary organizing structure; meetings are inputs.

## What It Does

- Scrapes and archives official city meeting documents (agendas, packets, minutes)
- Extracts topics, motions, votes, and committee membership from meeting records
- Generates AI summaries with citations back to source documents
- Presents everything in a resident-friendly interface organized around civic topics

## Design System

The site uses an **Atomic-era design system** inspired by 1950s-60s post-war optimism — Lustron houses, Formica countertops, Franciscan dinnerware, Googie architecture. The aesthetic conveys warmth and hope, wrapping civic watchdog tooling in the visual language of a mid-century living room.

### Two Themes

- **Living Room** (public pages) — warm cream backgrounds, terra cotta accents, full decorative vocabulary (starbursts, boomerangs, orbital rings). Tone: "Come sit down, here's what happened at city hall."
- **Silo** (admin pages) — cool concrete backgrounds, deep teal dominance, minimal decoration (atom markers, radar sweeps). The Titan missile silo aesthetic — serious infrastructure underneath the community.

### Typography

| Role | Font | Usage |
|------|------|-------|
| **Display** | [Outfit](https://fonts.google.com/specimen/Outfit) | Headings, stats, nav labels. Always uppercase, tight tracking. |
| **Body** | [Space Grotesk](https://fonts.google.com/specimen/Space+Grotesk) | Paragraphs, buttons, forms. Readable at all sizes. |
| **Data** | [DM Mono](https://fonts.google.com/specimen/DM+Mono) | Metadata, timestamps, status chips. Uppercase, wide tracking. |

### Color Palette

| Color | Hex | Role |
|-------|-----|------|
| Deep Teal | `#004a59` | Primary headings, links, nav chrome |
| Terra Cotta | `#c2522a` | Accent, action, section labels |
| Amber | `#d4872a` | Warnings, active states |
| Forest Green | `#2a7a4a` | Success states |
| Brick Red | `#9e2a2a` | Danger, errors |

Full spec with SVG motif path data, component patterns, spacing scale, and CSS architecture: **[`docs/plans/2026-03-28-atomic-design-system-spec.md`](docs/plans/2026-03-28-atomic-design-system-spec.md)**

## Tech Stack

- **Ruby on Rails 8.1** — server-rendered HTML, Turbo/Stimulus, ImportMap, Propshaft
- **PostgreSQL** with pgvector for embeddings
- **Solid Queue** for background jobs, **Solid Cache**, **Solid Cable**
- **OpenAI API** via `ruby-openai` for summarization and topic extraction
- **Plain CSS** with custom properties (no preprocessor) — single `application.css` file
- **Google Fonts** — Outfit, Space Grotesk, DM Mono

## Key Documents

| Document | Purpose |
|----------|---------|
| [`CLAUDE.md`](CLAUDE.md) | AI coding agent instructions — architecture, conventions, commands |
| [`docs/DEVELOPMENT_PLAN.md`](docs/DEVELOPMENT_PLAN.md) | Authoritative product spec and architectural constraints |
| [`docs/plans/2026-03-28-atomic-design-system-spec.md`](docs/plans/2026-03-28-atomic-design-system-spec.md) | Visual design system — colors, typography, motifs, components |
| [`docs/topics/TOPIC_GOVERNANCE.md`](docs/topics/TOPIC_GOVERNANCE.md) | Topic extraction, classification, and lifecycle rules |

## Getting Started

```bash
bin/setup --skip-server   # Install deps + prepare DB
bin/dev                   # Start dev server
bin/jobs                  # Start background job worker (separate terminal)
```

## Non-Goals

- No SPA — server-rendered HTML everywhere
- No microservices
- No commenting system
- No public user accounts

## License

TBD
