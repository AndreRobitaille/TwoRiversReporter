# Meeting Show Page Redesign

**Date:** 2026-03-01
**Issue:** Meeting detail pages — wrong first impression + wall of text

## Problem

The meeting show page has two problems:

1. **Wrong first impression.** A resident lands on the page and sees a
   collapsible "Topic Analysis" section (dense AI per-topic summaries)
   followed by a 500+ word "Meeting Recap" wall of text. The most
   useful navigational element — topic cards — is buried at the bottom.
   On mobile, you scroll past two screens of prose before reaching
   anything scannable.

2. **Wall of text.** The AI meeting recap is a markdown blob rendered as
   prose. No resident is reading 500+ words on their phone during a
   casual check-in. The content is good, but the format doesn't serve
   the audience.

Per `docs/AUDIENCE.md`: residents are scanners (not studiers),
mobile-heavy, and follow topics (not meetings). They want the gist
fast. A meeting page should tell them what happened, what topics were
discussed, and what was decided — in that order, without scrolling.

## Design

### Principle: Inverted Pyramid + Unified Agenda Items

Same principle as the topic show page redesign: most important
information first, all sections always visible. Additionally, meeting
content is organized by agenda item — discussion summaries, public
hearing input, and votes are shown inline with the item they belong to,
not in separate sections.

### Section Order

| # | Section | Data Source | Visual Treatment |
|---|---------|-------------|-----------------|
| 1 | Header | Meeting fields | Name, date, status badge, committee, city website link. Always present. |
| 2 | Headline | `generation_data.headline` | 1-2 sentences, prominent text. What happened at this meeting. |
| 3 | Highlights | `generation_data.highlights` | 3 bullets, highest impact first. Citations and vote tallies inline. |
| 4 | Public Input | `generation_data.public_input` | General public comment speakers + communications from council/committee members. Who spoke/wrote, what about. |
| 5 | Agenda Items | `generation_data.item_details` + `meeting.agenda_items` | Each substantive item as a card: title, editorial summary (2-4 sentences), public hearing input, decision/vote, topic pills. Procedural items filtered out. |
| 6 | Topics in This Meeting | `@ongoing_topics` + `@new_topics` | Topic cards (existing partial). Split into Ongoing / New. Navigation to topic pages, not meeting content. |
| 7 | Documents | `meeting.meeting_documents` | Download links. |

### Empty State Messages

| Section | Message |
|---------|---------|
| Headline + Highlights | "No summary available for this meeting yet." |
| Public Input | "No public comments or communications recorded for this meeting." |
| Agenda Items | "No agenda items available for this meeting." |
| Topics | "No topics have been identified for this meeting." |
| Documents | "No documents available for this meeting." |

### Structured JSON Rendering

**Current flow:** Pass 1 → structured JSON (discarded) → Pass 2 →
markdown blob → rendered as prose wall of text.

**New flow:** Pass 1 → structured JSON → stored in
`MeetingSummary.generation_data` → ERB renders directly from JSON.

Pass 2 is dropped. The existing `content` (markdown) field stays as
fallback for meetings without `generation_data` until backfill runs.

### `generation_data` Schema

```json
{
  "headline": "Council approved $2.5M borrowing 6-3, tabled property
               assessment policy, discussed Neshotah Beach improvements.",
  "highlights": [
    {
      "text": "Adopted intent-to-reimburse resolution for up to $2,563,818
               in 2026 capital spending",
      "citation": "Page 3",
      "vote": "6-3",
      "impact": "high"
    },
    {
      "text": "Tabled proposed property assessment policy ordinance",
      "citation": "Page 2",
      "vote": null,
      "impact": "high"
    },
    {
      "text": "Discussed Neshotah Beach concessions improvement survey
               and $255K financing conditions",
      "citation": "Page 3",
      "vote": null,
      "impact": "medium"
    }
  ],
  "public_input": [
    {
      "speaker": "Jim Bob Scoot",
      "type": "public_comment",
      "summary": "Raised concerns about Historic Farm Museum building
                  condition — bricks exposed, internal structures visible"
    },
    {
      "speaker": "Councilmember Shimulunas",
      "type": "communication",
      "summary": "Contacted by resident about Neshotah Beach parking
                  and garbage issues"
    }
  ],
  "item_details": [
    {
      "agenda_item_title": "Rezoning at 3204 Lincoln Ave",
      "summary": "Plan Commission recommended approval of rezoning from
                  IPF to R-3 for two newly created lots. Standard lot
                  split enabling residential development on the parcel.",
      "public_hearing": "Three calls for public input. No one spoke.",
      "decision": "Passed unanimously",
      "vote": "7-0",
      "citations": ["Page 2"]
    },
    {
      "agenda_item_title": "Property Assessment Policy Ordinance",
      "summary": "Introduced with committee recommendation to adopt.
                  Council chose to table rather than vote, signaling
                  unresolved concerns about the policy's scope.",
      "public_hearing": null,
      "decision": "Tabled",
      "vote": null,
      "citations": ["Page 2"]
    }
  ]
}
```

**Key schema decisions:**

- `headline` is 1-2 sentences, backward-looking, max ~40 words. Written
  in editorial voice per AUDIENCE.md.
- `highlights` is max 3 items, highest impact first. Each has optional
  `vote` tally and `citation`.
- `public_input` distinguishes `public_comment` (resident spoke at
  podium) from `communication` (member relayed resident contact).
  Addresses redacted.
- `item_details` covers substantive agenda items only. Each gets 2-4
  sentences of editorial summary, optional `public_hearing` note,
  optional `decision` and `vote` tally. Procedural items (adjourn,
  minutes approval, consent agenda, remote participation, treasurer's
  report) are excluded by the AI prompt.
- All text fields use plain language per AUDIENCE.md — no government
  jargon, no "Motion to waive reading and adopt the ordinance to
  amend..." language.

### Procedural Motion Filter

The Key Decisions section from the old layout is eliminated — votes are
shown inline with their agenda items via `item_details`. However, the
AI prompt must also filter procedural items from `item_details`. The
following patterns are excluded:

| Pattern | Example |
|---------|---------|
| Adjourn | "Motion to dispense with reading and adjourn" |
| Minutes approval | "Motion to approve the January 7 meeting minutes" |
| Consent agenda | "Motion to approve the Consent Agenda as presented" |
| Remote participation | "Approve Councilmember X from a remote location" |
| Treasurer's report | "Motion to approve the Treasurer's Report" |
| Reconvene in open session | "Motion to reconvene in open session" |

**Closed session motions are NOT filtered** — they contain statutory
justification (Wis. Stats 19.85) that residents should see for open
meetings law transparency.

### Per-Topic Summaries: Dropped from Meeting Page

The current collapsible "Topic Analysis" section (per-topic AI
summaries via `TopicSummary`) is removed from the meeting show page.
Topic cards in section 6 link to topic pages where residents get the
full story. Showing both per-topic summaries AND topic cards is
redundant — the topic page is the right place for topic-level analysis.

`TopicSummary` records still exist and are still generated by the
pipeline. They feed into `TopicBriefing` generation. They just don't
render on the meeting show page.

### Public Input Section

Minutes contain three types of public input:

1. **General public comment** — Residents speak at an open comment
   period about any topic. Unrelated to specific agenda items. Listed
   in the Public Input section with speaker name and brief summary.

2. **Communications from the public** — Council/committee members
   mention contacts they received (emails, calls, letters). Listed in
   Public Input with the relaying member's name and summary.

3. **Item-specific public hearing** — Formal public input on specific
   items (CUPs, rezonings). Three calls for input per Wisconsin law.
   Shown inline with the agenda item in `item_details.public_hearing`.

Types 1 and 2 go in the standalone Public Input section. Type 3 goes
with the agenda item.

### Agenda Item Cards

Each substantive agenda item renders as a card-like element:

```
┌─────────────────────────────────────────────────┐
│ 6.A  Rezoning at 3204 Lincoln Ave               │
│                                                  │
│ Plan Commission recommended approval of          │
│ rezoning from IPF to R-3 for two newly           │
│ created lots...                     [Page 2]     │
│                                                  │
│ Public Input: Three calls. No one spoke.         │
│                                                  │
│ ✓ Passed 7-0                                     │
│                                                  │
│ [rezoning]  [lincoln ave]                        │
└─────────────────────────────────────────────────┘
```

- Item number + title at top
- Editorial summary (2-4 sentences, from `item_details.summary`)
- Public hearing note if applicable
- Decision + vote tally (color-coded: green for passed, red for failed,
  amber for tabled)
- Topic pills linking to topic pages

Items without AI detail (no `generation_data` match) show just the
title from the database `AgendaItem` record, with any linked topic
pills.

### Pipeline Changes

**Migration:** Add `generation_data` (jsonb) to `meeting_summaries`.

**SummarizeMeetingJob:** Modify `generate_meeting_summary` to store
Pass 1 JSON in `generation_data`. Drop the Pass 2 call
(`render_meeting_summary`). The `content` field is no longer populated
for new summaries.

**OpenAI prompt:** Rewrite `analyze_meeting_content` to produce the
new schema (`headline`, `highlights`, `public_input`, `item_details`).
The prompt must:

- Write in editorial voice per AUDIENCE.md (plain language, skeptical
  of process, editorialize early)
- Exclude procedural items from `item_details`
- Distinguish general public comment from item-specific public hearing
- Include vote tallies where votes occurred
- Redact residential addresses in public comments
- Anchor citations to page numbers

The current Pass 1 prompt already produces `top_topics`,
`public_comments`, `framing_notes`, `decision_hinges`, and
`official_discussion`. The new schema consolidates these into a
per-item structure and adds the headline and highlights.

**Backfill:** Rake task to re-summarize existing meetings that have
minutes or packet text. Old `content` (markdown) stays as fallback
until backfilled. The view checks `generation_data` first, falls back
to rendering `content` in a prose block.

### One Pass, Test and Iterate

The design uses a single AI pass (no Pass 2 rendering step). This
saves one API call per meeting and simplifies the pipeline. The
editorial voice is produced directly in the structured JSON fields.

If testing on real council meetings shows that per-item summaries are
too thin (especially for 2-hour meetings with 10-15 substantive items),
we may add Pass 2 back as a structured JSON enrichment step (not
markdown). Start with one pass, test on real data, adjust if needed.

## What Does NOT Change

- `TopicSummary` pipeline (per-topic per-meeting, still two-pass,
  still feeds `TopicBriefing`)
- `TopicBriefing` pipeline and topic show page
- `ExtractTopicsJob`, `ExtractVotesJob`, `ExtractCommitteeMembersJob`
- Homepage, topics index, meetings index
- `MeetingSummary` model associations (beyond accepting new column)
- `Motion` and `Vote` models (motion-to-agenda-item linking is
  tracked in GitHub issue #76, separate scope)
- Topic card partial (`topics/_topic_card`)
- Admin views

## Files to Modify

- `db/migrate/..._add_generation_data_to_meeting_summaries.rb` — Add
  `generation_data` (jsonb) column
- `app/jobs/summarize_meeting_job.rb` — Store Pass 1 JSON in
  `generation_data`, drop Pass 2 call
- `app/services/ai/open_ai_service.rb` — Rewrite
  `analyze_meeting_content` prompt for new schema with editorial voice
- `app/views/meetings/show.html.erb` — Rewrite with fixed section
  order, structured JSON rendering, empty states, unified agenda items
- `app/helpers/meetings_helper.rb` — Add helpers for `generation_data`
  field extraction, procedural motion filtering
- `app/controllers/meetings_controller.rb` — Expose `generation_data`
  via `@summary`
- `app/assets/stylesheets/application.css` — Agenda item card styles,
  public input section, highlight bullets, decision badges

## Files NOT Modified

- AI prompts for topic summarization / briefings
- TopicSummary, TopicBriefing models
- Topic show page, topics index, homepage
- ExtractTopicsJob, ExtractVotesJob
- Meeting model
- Any admin views

## Related

- **GitHub #76** — Link motions to agenda items in ExtractVotesJob
  (separate scope, enables database-backed vote grids per item later)
- **Design doc:** `docs/plans/2026-03-01-topic-show-consistent-layout-design.md`
  (topic page redesign this follows)
- **Design doc:** `docs/plans/2026-03-01-minutes-triggered-reextraction-design.md`
  (pipeline improvement completed in this session)

## Verification

After implementation:

1. Re-summarize a council meeting with minutes (e.g., meeting 131) —
   verify `generation_data` has headline, highlights, public_input,
   item_details
2. Re-summarize a subcommittee meeting (e.g., Public Works 130) —
   verify smaller meetings produce adequate detail
3. Check the meeting show page renders all sections with proper
   empty states for a meeting with no summary yet
4. Check fallback: a meeting with old markdown `content` but no
   `generation_data` should render the prose block
5. Compare editorial quality of one-pass item summaries against the
   old two-pass markdown recap — decide if Pass 2 is needed
