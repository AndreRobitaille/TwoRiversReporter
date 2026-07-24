---
name: page-architecture
description: Use when working on the homepage, topic show page, meeting show page, or the YouTube transcript pipeline. Covers zone/section layouts, which helper reads which structured-JSON field, controller data flow, known layout issues, and pointers to the authoritative design specs.
---

# Page & Pipeline Architecture

Detailed layout and data-flow notes for the resident-facing pages. The design specs referenced in each section are authoritative — read them before changing layout.

## Homepage — Newspaper Layout (Apr 2026)

The homepage uses a newspaper-style inverted pyramid layout. Four zones, top to bottom:

1. **Top Stories (1-2 items)**: Highest-impact topics with recent activity. Full cards with topic name, description, briefing headline, meeting reference, "Meeting details →" button. Uses `_top_story.html.erb` partial.
2. **The Wire (4 cards + 6 rows)**: Next tier by impact. Mid-tier cards in 2-col grid (`_wire_card.html.erb`), compact rows below (`_wire_row.html.erb`). Cards link to meetings; rows link to topics.
3. **Next Up (1-2)**: Next council meeting and/or work session. Calendar-style date slabs with terra-cotta (council) or teal (work session) coloring. Uses `_next_up.html.erb`.
4. **Escape Hatches**: "Browse All Topics →" and "All Meetings →" buttons.

**Data flow**: `HomeController` builds `@top_stories` (impact ≥ 4, 30d window), `@wire_cards`/`@wire_rows` (impact ≥ 2, excludes top stories), `@next_up` (council/work session patterns via the `COUNCIL_PATTERNS` constant), `@headlines` (from `TopicBriefing`), `@meeting_refs` (most recent meeting appearance per topic).

**Sort order**: Impact score descending, then recency. NOT chronological. No committee filtering — subcommittee topics surface naturally by impact.

**CSS**: `app/assets/stylesheets/home.css` — homepage-specific styles. Three visual tiers with decreasing card weight. Atomic motifs (starburst, diamond dividers, atom markers). Explicit click affordances on all interactive elements.

**Known issue**: Top story and wire card links go to meeting pages, which may have thin content (no minutes/transcript). Plan to switch to topic page links once topic pages are improved (see #63, #76, #89).

**Design spec**: `docs/superpowers/specs/2026-04-10-homepage-redesign-design.md`

## Topic Navigation Pattern

Topic cards (`topics/_topic_card` partial) are the primary navigation element to topic pages. The same partial is reused on the topics index (hero + list) and meeting show page ("Issues in This Meeting" section). Meeting show page splits topics into "Ongoing" (2+ appearances) and "New This Meeting" (1 appearance) subsections. Homepage meeting row topic pills are filtered to `resident_impact_score >= 2`.

## Topic Show Page

The topic show page (`topics/show.html.erb`) uses an **editorial longform layout** — a single 38rem centered reading column, section visibility adapts to data availability, typography (not container chrome) differentiates sections. Section order: Header → What to Watch → Coming Up → The Story → Key Decisions → Record.

**Layout structure:** `<article class="topic-article">` wraps all content in a 38rem max-width column. Two reading measures:
- **38rem (container)** — eyebrows, dek, story body, decision desc, Coming Up fallback, Record events
- **30rem (narrower)** — pullquote (What to Watch) and aside (Worth noting). Clearly pulled-out indented content.

**Section visibility** is adaptive. Sections render only when they have content:
- `What to Watch` — hidden when no briefing
- `Coming Up` — renders meeting cards when future meetings exist; shows "typically discussed at [committee]" fallback (from `@typical_committee`) when no upcoming but appearance history exists; hidden if neither
- `The Story` — hidden when no briefing
- `Key Decisions` — hidden when `@decisions.any?` is false (motion→agenda_item linking via `agenda_item_ref` required)
- `Record` — always shown (every topic has ≥1 appearance). Empty state only when `factual_record` is empty.

**Structured JSON rendering:** Briefing content renders from `TopicBriefing.generation_data` (pass 1 structured JSON). Helpers in `TopicsHelper`: `briefing_what_to_watch`, `briefing_current_state`, `briefing_process_concerns`, `briefing_factual_record`, `format_record_date`, `enrich_record_entry`, `clean_meeting_display`. Markdown fields (`editorial_content`, `record_content`) are fallbacks for briefings without `generation_data` — `briefing_current_state` falls back to `editorial_content` for `headline_only` tier briefings.

**Record enrichment:** `enrich_record_entry` cross-references each factual_record entry with `TopicAppearance` records (grouped by date in `@record_meetings`) using `normalize_meeting_name` for fuzzy matching (strips trailing " Meeting", `(CANCELED)`, date suffixes, separator differences). When matched, "appeared on the agenda" placeholder text is replaced with the matching `MeetingSummary.generation_data["item_details"]` summary (truncated 200 chars) or the agenda item title as a fallback. Meeting name renders as a link to the canonical `meeting_path` with the cleaned body_name.

**Motion→agenda_item linking:** `ExtractVotesJob` passes `agenda_items_text` to the `extract_votes` prompt template. AI returns `agenda_item_ref` per motion (item number and/or title). `resolve_agenda_item` matches refs against real `AgendaItem` records: item number exact match first (handles bare numbers like "7a"), then word-overlap title similarity with 0.5 threshold. Unmatched motions (consent agenda batches, procedural) keep `agenda_item_id: nil`. Enables the Key Decisions section on topic pages.

**Key CSS classes** live in `application.css` around lines 1815–2200, prefixed `.topic-article*`, `.topic-watch-*`, `.topic-upcoming-*`, `.topic-story-*`, `.topic-aside*`, `.topic-decision*`, `.topic-timeline*`. `.home-section-header` is reused from the homepage (atom marker + label + gradient line). `.topic-story-body` carries the `::first-letter` drop cap via `initial-letter: 2`.

**Design spec:** `docs/superpowers/specs/2026-04-10-topic-page-overhaul-design.md`
**Implementation plan:** `docs/superpowers/plans/2026-04-10-topic-page-overhaul.md`

**Backfill still owed:** `ExtractVotesJob` now links motions to agenda items via `agenda_item_ref`, but historical `Motion.agenda_item_id` values are unpopulated — run `ExtractVotesJob.perform_later(m.id)` for every meeting with minutes.

**Remaining issues:**
- **Coming Up empty most of the time** — agendas not published far in advance. Fallback shows typical committee, but no scheduled date.
- **Homepage link targets still go to meetings** — can switch to topic page links now that topic pages are credible, but that's a separate change.

## Meeting Show Page

The meeting show page (`meetings/show.html.erb`) uses a **fixed inverted-pyramid layout** — all sections always render, with empty state messages (`.section-empty`) when data is absent. Section order: Header → Headline → Highlights → Public Input → Agenda Items → Topics → Documents.

**Structured JSON rendering:** Meeting summary content renders from `MeetingSummary.generation_data` (single-pass structured JSON from `analyze_meeting_content`) instead of two-pass markdown. Helper methods in `MeetingsHelper` extract fields: `meeting_headline`, `meeting_highlights`, `meeting_public_input`, `meeting_item_details`, `decision_badge_class`. The `content` (markdown) field is a fallback for meetings without `generation_data`, rendered in `.meeting-legacy-recap`.

**Single-pass pipeline:** `SummarizeMeetingJob` calls `analyze_meeting_content` directly and stores the structured JSON in `generation_data`. The old two-pass flow (analyze → render markdown) is bypassed. The `render_meeting_summary` method remains for backward compatibility but is not called by the job.

**Procedural filtering:** the AI prompt excludes adjournment, minutes approval, consent agenda, remote participation, treasurer's report, and reconvene. Closed session motions are NOT filtered (Wis. Stats 19.85 transparency).

**Public input types:** `public_comment` (resident at podium) vs `communication` (member relayed contact). Item-specific public hearings go in `item_details.public_hearing`.

**Key CSS classes:** `.meeting-headline`, `.meeting-highlights`, `.highlight-vote`, `.highlight-citation`, `.public-input-list`, `.public-input-item`, `.meeting-item-card`, `.decision-badge` with `--passed`/`--failed`/`--tabled`/`--default` variants.

**Design doc:** `docs/plans/2026-03-01-meeting-show-redesign-design.md`

## YouTube Transcript Pipeline

Council meetings and work sessions are recorded and posted to YouTube (`@Two_Rivers_WI`). The transcript pipeline ingests auto-generated captions to produce same-day preliminary summaries, then enriches minutes-based summaries when official minutes arrive.

**Job chain:** `DiscoverMeetingsJob` (daily 11pm) → `DiscoverTranscriptsJob` → `DownloadTranscriptJob` → `SummarizeMeetingJob`

**Title pattern:** `Two Rivers City Council [Meeting|Work Session] for [Day], [Month] [Date], [Year]` — very consistent, parsed by regex.

**`Scrapers::DiscoverTranscriptsJob`** — Queries for Council Meeting / Work Session meetings in the last 48 hours without a transcript document. Runs `yt-dlp --flat-playlist` to list channel videos, parses titles with `TITLE_PATTERN` regex to extract dates, matches to Meeting records. Channel URL and body names are constants on the class.

**`Documents::DownloadTranscriptJob`** — Takes `(meeting_id, video_url)`. Validates URL against `YOUTUBE_URL_PATTERN`, fetches SRT via `yt-dlp` in a temp directory, parses SRT to plain text (strips timestamps/sequence numbers), creates `MeetingDocument` with `document_type: "transcript"`, attaches raw SRT file. Enqueues `SummarizeMeetingJob` if no `minutes_recap` summary exists.

**Transcript is a supplement, not a replacement** — it never overrides official sources. Used as the primary source only when no minutes exist (produces `transcript_recap`). When minutes arrive, transcript text (truncated to 15K chars) is appended as supplementary context and `source_type` becomes `"minutes_with_transcript"`. Old `transcript_recap` summaries are cleaned up when minutes arrive.

**Transcript banner:** Meeting show page displays a cool-toned `.transcript-banner` when `generation_data["source_type"] == "transcript"`. Automatically removed when a minutes-based summary replaces it.

**Agenda preview banner:** Same banner style when `source_type == "agenda"`. Copy is time-aware — future meetings read "This meeting hasn't happened yet — check back for a full recap after minutes are published"; past meetings read "Official minutes have not yet been published." Banner disappears once packet/transcript/minutes supersede the agenda preview.

**Infrastructure:** `yt-dlp` standalone binary (`yt-dlp_linux`) installed in Dockerfile. No Python dependency. **Known issue (#87):** YouTube rate-limits/bot-detects requests from datacenter IPs. Local `yt-dlp` works fine; the production server gets "Sign in to confirm you're not a bot". Current workaround: download SRTs locally, import via the `transcripts:import` rake task.

**Design doc:** `docs/superpowers/specs/2026-04-09-youtube-transcript-ingestion-design.md`
