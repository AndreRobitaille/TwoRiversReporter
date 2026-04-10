# Topic Page Overhaul — Unified Design Spec

**Issues:** #63 (UX overhaul), #76 (motion → agenda item linking), #89 (Record enrichment)
**Date:** 2026-04-10
**Goal:** Make the topic page good enough to be the primary destination from the homepage.

## Decisions Made

- **Motion linking (#76):** Hybrid approach — AI suggests agenda item reference text, code validates against real AgendaItem records by item number then title similarity.
- **Record enrichment (#89):** View-layer enrichment — cross-reference factual_record entries with MeetingSummary data at render time. No AI regeneration needed.
- **Empty sections (#63):** Adaptive per-section rules — hide Key Decisions when no linked motions, show "typically discussed at [committee]" fallback for Coming Up, always show Record and Story.
- **Visual scope (#63):** Affordance + hierarchy pass — fix clickability signals, apply design system consistently, reuse homepage/meeting-show patterns. No layout restructure.

---

## Phase 1: Motion-to-Agenda-Item Linking (#76)

### Problem

`ExtractVotesJob` creates Motion records but never sets `agenda_item_id`. The column exists, the `belongs_to :agenda_item, optional: true` association exists, but the AI prompt doesn't include agenda item context and the job doesn't attempt matching.

### Changes

#### 1. Prompt Template Update (`extract_votes`)

Add a new placeholder `{{agenda_items}}` to the extract_votes prompt. The prompt instructs the AI to return an `agenda_item_ref` field per motion — a free-text reference to the agenda item the motion belongs to (item number, title, or both). NOT a database ID.

Updated schema in prompt:
```json
{
  "motions": [
    {
      "description": "Text of the motion",
      "outcome": "passed | failed | tabled | other",
      "agenda_item_ref": "7a: Lead Service Line Replacement Program" | null,
      "votes": [
        { "member": "Member Name", "value": "yes | no | abstain | absent | recused" }
      ]
    }
  ]
}
```

Rules for the AI:
- `agenda_item_ref` should reference the agenda item number and/or title as written in the agenda
- For consent agenda batch motions or procedural motions (adjournment, minutes approval), set to `null`
- When a single motion covers multiple items, use the most specific single item

#### 2. PromptTemplate Placeholder Registration

Add `agenda_items` to the placeholder list for `extract_votes` in `lib/prompt_template_data.rb`.

#### 3. ExtractVotesJob Changes

**Build agenda item context:**
```ruby
agenda_items = meeting.agenda_items.map { |ai|
  { id: ai.id, item_number: ai.item_number, title: ai.title }
}
agenda_items_text = agenda_items.map { |ai|
  ai[:item_number].present? ? "#{ai[:item_number]}: #{ai[:title]}" : ai[:title]
}.join("\n")
```

Pass `agenda_items_text` as the `agenda_items` placeholder.

**Match agenda_item_ref to real records:**

New private method `resolve_agenda_item(ref, agenda_items)`:
1. Return `nil` if `ref` is blank
2. Extract item number from ref (e.g., "7a" from "7a: Lead Service Lines") — match against `AgendaItem.item_number` (case-insensitive)
3. If no item number match, fuzzy-match ref against agenda item titles — use simple word overlap scoring. Accept match only above a threshold (e.g., 50% of words overlap).
4. Return matched `AgendaItem` or `nil`

**Create motion with agenda_item:**
```ruby
agenda_item = resolve_agenda_item(m_data["agenda_item_ref"], meeting.agenda_items)
motion = meeting.motions.create!(
  description: m_data["description"],
  outcome: m_data["outcome"],
  agenda_item: agenda_item
)
```

#### 4. OpenAiService Changes

Update `extract_votes` method signature to accept agenda item context:
```ruby
def extract_votes(text, agenda_items_text: "", source: nil)
```

Add `agenda_items` to placeholders hash:
```ruby
placeholders = { text: text.truncate(50_000), agenda_items: agenda_items_text }
```

#### 5. Backfill

After deploying, re-run `ExtractVotesJob` for all meetings that have minutes. The job is already idempotent (clears + rebuilds motions in a transaction). A rake task or runner loop:
```ruby
Meeting.joins(:meeting_documents)
  .where(meeting_documents: { document_type: "minutes_pdf" })
  .find_each { |m| ExtractVotesJob.perform_later(m.id) }
```

### Not Changing

- Motion model schema — `agenda_item_id` column already exists
- Motion associations — `belongs_to :agenda_item, optional: true` already set
- AgendaItem model — `has_many :motions` already set
- `TopicsController#show` `@decisions` query — already joins through `agenda_item: :agenda_item_topics`, will start returning results once `agenda_item_id` is populated

---

## Phase 2: Record Enrichment + Meeting Links (#89)

### Problem

Record timeline entries come from `TopicBriefing.generation_data["factual_record"]` — an array of `{ date, event, meeting }` hashes. Most entries say "appeared on the agenda." Meeting names are plain text, not links.

### Changes

#### 1. Controller: Load Record Meeting Lookup

In `TopicsController#show`, build a hash mapping record entries to actual Meeting records:

```ruby
# Record enrichment: map (date, body_name) → Meeting for linking
appearances = @topic.topic_appearances
                    .includes(meeting: :meeting_summaries)
                    .index_by { |a| "#{a.appeared_at.to_date}:#{a.meeting.body_name}" }
@record_meetings = appearances
```

This gives the view O(1) lookup per record entry.

#### 2. Helper: Enrich Record Entries

New method `enrich_record_entry(entry, record_meetings)` in `TopicsHelper`:

```ruby
def enrich_record_entry(entry, record_meetings)
  key = "#{entry['date']}:#{entry['meeting']}"
  appearance = record_meetings[key]
  meeting = appearance&.meeting

  # Enrich "appeared on the agenda" with real content
  event_text = entry["event"]
  if event_text.match?(/appeared on the agenda/i) && meeting
    enriched = extract_meeting_item_summary(meeting, @topic)
    event_text = enriched if enriched.present?
  end

  { event: event_text, meeting_name: entry["meeting"], meeting: meeting }
end
```

`extract_meeting_item_summary(meeting, topic)` — new private helper:
1. Check `meeting.meeting_summaries` for a summary with `generation_data["item_details"]`
2. Find the item detail whose title best matches any of the topic's agenda item titles for that meeting
3. Return the item's summary/description text (truncated to ~200 chars for the timeline)
4. Fall back to the agenda item title from `TopicAppearance.agenda_item.title`
5. Return `nil` if nothing found (keeps original text)

#### 3. View: Render Links + Enriched Text

Update the Record section in `topics/show.html.erb`:

```erb
<% record_entries.each do |entry| %>
  <% enriched = enrich_record_entry(entry, @record_meetings) %>
  <div class="topic-timeline-entry">
    <div class="topic-timeline-date">
      <%= format_record_date(entry["date"]) %>
    </div>
    <div class="topic-timeline-content">
      <%= enriched[:event] %>
      <% if enriched[:meeting] %>
        <%= link_to enriched[:meeting_name], meeting_path(enriched[:meeting]),
            class: "topic-timeline-meeting-link" %>
      <% else %>
        <span class="topic-timeline-meeting"><%= enriched[:meeting_name] %></span>
      <% end %>
    </div>
  </div>
<% end %>
```

### Not Changing

- TopicBriefing generation — no prompt changes, no regeneration
- `factual_record` JSON structure — same `{ date, event, meeting }` shape
- MeetingSummary content — read-only consumption

---

## Phase 3: Visual/UX Overhaul (#63)

### Affordance Fixes

All interactive elements must signal clickability to the 35+ audience:

- **Links in body text:** `text-decoration: underline` by default, `color` shift on hover
- **Card components:** `cursor: pointer`, `box-shadow` elevation on hover, subtle `transform: translateY(-1px)` on hover
- **Record meeting links:** Styled as inline links (underline + color), not plain text
- **Coming Up cards:** Already have `card-link--upcoming` class — add hover elevation
- **Back button:** Already styled as `.btn--secondary` — adequate

### Section Hierarchy

Apply consistent design system treatment across all sections:

- **Diamond dividers** (`shared/_diamond_divider` partial) between major sections (after What to Watch, after Coming Up, after The Story, after Key Decisions). Same pattern used on homepage.
- **Section headers:** Outfit uppercase font, `letter-spacing: 0.05em`, bottom border in `var(--color-primary)`. Already partially implemented — make consistent across all sections.
- **Visual weight:** Top sections (What to Watch, Coming Up) get warm accent colors. Middle sections (Story, Key Decisions) get neutral treatment. Record section gets muted, archival feel.

### Key Decisions Section

Reuse patterns from meeting show page:

- **Decision badges:** `.decision-badge` with `--passed`/`--failed`/`--tabled` variants (already exist in meeting show CSS)
- **Vote tally:** Show "Passed 7-0" or "Failed 3-4" in the badge (already implemented in `motion_outcome_text` helper)
- **Meeting link:** Add "at [Committee Name], [Date]" with link to meeting page
- **Hidden when empty:** Replace `<p class="section-empty">` with a conditional that hides the entire section when `@decisions.empty?`

### Coming Up Section

Adaptive behavior:

**When upcoming meetings exist (current behavior, with visual upgrade):**
- Calendar-slab style from homepage `_next_up.html.erb` — date displayed prominently, body name as subtitle
- Terra-cotta accent for council meetings, teal for work sessions (match homepage color logic)
- Link to meeting page with explicit "View meeting →" button

**When no upcoming meetings exist (new fallback):**
- Derive the most frequent committee from `TopicAppearance` history:
  ```ruby
  @typical_committee = @topic.topic_appearances
                             .group(:body_name)
                             .order("count_all DESC")
                             .limit(1)
                             .count
                             .keys
                             .first
  ```
- Render: "This topic is typically discussed at **[Committee Name]**. Check back when the next agenda is published."
- If no appearances at all (shouldn't happen for visible topics), hide the section entirely.

### Record Section — Visual Enhancements

- **Substantive entries** (enriched text, not "appeared on the agenda") get normal text weight
- **Meeting links** styled as inline links with underline
- **Timeline connecting line** — already exists via `.topic-timeline::before`, keep as-is
- **Date column** — keep right-aligned DM Mono uppercase styling (matches design system data role)

### CSS Organization

All changes go in existing `app/assets/stylesheets/application.css` under the topic section styles. New classes:

- `.topic-timeline-meeting-link` — inline link style for Record meeting names
- `.topic-coming-up-fallback` — muted text style for "typically discussed at" message
- `.topic-decision-meeting-ref` — small text for meeting reference in Key Decisions

Reuse existing classes from homepage/meeting-show: `.decision-badge`, `.decision-badge--passed`, etc.

### Section Visibility Rules Summary

| Section | When to show | Empty state |
|---------|-------------|-------------|
| Header | Always | N/A (topic always has a name) |
| What to Watch | When `briefing_what_to_watch` returns text | Hidden |
| Coming Up | When upcoming meetings exist OR topic has appearance history | "Typically discussed at [committee]" fallback |
| The Story | When `briefing_current_state` returns text | Hidden |
| Key Decisions | When `@decisions.any?` | Hidden entirely (no header, no section) |
| Record | Always (every topic has ≥1 appearance) | N/A |

---

## Files Changed

### Phase 1
- `app/jobs/extract_votes_job.rb` — add agenda item context, resolve `agenda_item_ref`
- `app/services/ai/open_ai_service.rb` — add `agenda_items_text` param to `extract_votes`
- `lib/prompt_template_data.rb` — add `agenda_items` placeholder to extract_votes template
- `db/seeds/prompt_templates.rb` (or migration) — update extract_votes prompt text in database

### Phase 2
- `app/controllers/topics_controller.rb` — add `@record_meetings` lookup
- `app/helpers/topics_helper.rb` — add `enrich_record_entry`, `extract_meeting_item_summary`
- `app/views/topics/show.html.erb` — use enrichment helper, render meeting links

### Phase 3
- `app/views/topics/show.html.erb` — section visibility conditionals, diamond dividers, Coming Up fallback, Key Decisions visual upgrade
- `app/controllers/topics_controller.rb` — add `@typical_committee` for Coming Up fallback
- `app/assets/stylesheets/application.css` — affordance styles, new CSS classes
- `app/helpers/topics_helper.rb` — any new view helpers needed

### Tests
- `test/jobs/extract_votes_job_test.rb` — test agenda item matching (exact number, fuzzy title, nil fallback)
- `test/helpers/topics_helper_test.rb` — test `enrich_record_entry`, `extract_meeting_item_summary`
- `test/controllers/topics_controller_test.rb` — test `show` loads new instance variables
- `test/views/topics/show_test.rb` or system test — test section visibility rules

### Documentation
- `CLAUDE.md` — update Known Issues section (remove resolved items), document new behavior
- GitHub issues #63, #76, #89 — close with references to commits

---

## What This Enables (Follow-up Work)

Once this ships and topic pages are credible destinations:
- **Switch homepage links from meeting pages to topic pages** — top story cards and wire cards currently link to meetings because topic pages were too thin. After this work, switch to topic page links.
- **Member voting record by topic** — group a member's votes by topic via the new motion → agenda item → topic chain.
