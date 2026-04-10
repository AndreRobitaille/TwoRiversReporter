# Topic Page Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the topic show page a credible primary destination from the homepage by fixing the motion→agenda-item data gap (#76), enriching Record entries with meeting content (#89), and applying visual/UX improvements (#63).

**Architecture:** Three phases, each independently deployable. Phase 1 modifies the AI extraction pipeline to link motions to agenda items. Phase 2 adds view-layer enrichment to cross-reference Record entries with MeetingSummary data. Phase 3 applies design system patterns (affordances, section hierarchy, adaptive empty states) to the topic show page.

**Tech Stack:** Rails 8.1, Minitest, OpenAI API (via PromptTemplate), ERB views, CSS custom properties

**Design spec:** `docs/superpowers/specs/2026-04-10-topic-page-overhaul-design.md`

---

## File Structure

### Phase 1 — Motion-to-Agenda-Item Linking (#76)
- **Modify:** `app/jobs/extract_votes_job.rb` — Add agenda item context building, AI ref resolution
- **Modify:** `app/services/ai/open_ai_service.rb` — Add `agenda_items_text` keyword arg to `extract_votes`
- **Modify:** `lib/prompt_template_data.rb` — Update prompt text and placeholder list for `extract_votes`
- **Modify:** `db/seeds/prompt_templates.rb` — Add `agenda_items` placeholder to seed data
- **Create:** `test/jobs/extract_votes_job_test.rb` — Full test coverage for extraction + linking

### Phase 2 — Record Enrichment + Meeting Links (#89)
- **Modify:** `app/controllers/topics_controller.rb` — Add `@record_meetings` lookup in `show`
- **Modify:** `app/helpers/topics_helper.rb` — Add `enrich_record_entry`, `extract_meeting_item_summary`
- **Modify:** `app/views/topics/show.html.erb` — Use enrichment helper, render meeting links
- **Modify:** `test/helpers/topics_helper_test.rb` — Test enrichment helpers
- **Modify:** `test/controllers/topics_controller_test.rb` — Test new instance variables

### Phase 3 — Visual/UX Overhaul (#63)
- **Modify:** `app/views/topics/show.html.erb` — Section visibility, diamond dividers, Coming Up fallback, Key Decisions upgrade
- **Modify:** `app/controllers/topics_controller.rb` — Add `@typical_committee` for Coming Up fallback
- **Modify:** `app/assets/stylesheets/application.css` — Affordance styles, new CSS classes
- **Modify:** `test/controllers/topics_controller_test.rb` — Update section visibility tests

---

## Phase 1: Motion-to-Agenda-Item Linking (#76)

### Task 1: Update Prompt Template Data

**Files:**
- Modify: `lib/prompt_template_data.rb` — Update `extract_votes` prompt text and schema
- Modify: `db/seeds/prompt_templates.rb` — Add `agenda_items` placeholder to seed metadata

- [ ] **Step 1: Update the extract_votes prompt in `lib/prompt_template_data.rb`**

In `lib/prompt_template_data.rb`, find the `"extract_votes"` key in the `PROMPTS` hash and replace its value:

```ruby
    "extract_votes" => {
      system_role: "You are a data extraction assistant.",
      instructions: <<~PROMPT.strip
        <extraction_spec>
        You are a data extraction assistant. Extract formal motions and voting records from meeting minutes into JSON.

        - Always follow this schema exactly (no extra fields).
        - If a field is not present, set it to null.
        - Before returning, re-scan to ensure no motions were missed.

        Schema:
        {
          "motions": [
            {
              "description": "Text of the motion (e.g. 'Motion to approve the minutes')",
              "outcome": "passed" | "failed" | "tabled" | "other",
              "agenda_item_ref": "Item number and/or title from the agenda list below, or null",
              "votes": [
                { "member": "Member Name", "value": "yes" | "no" | "abstain" | "absent" | "recused" }
              ]
            }
          ]
        }
        </extraction_spec>

        <agenda_item_ref_rules>
        - Match each motion to the agenda item it belongs to using the agenda items list below.
        - Use the item number and/or title as written in the list (e.g. "7a: Lead Service Line Replacement").
        - For consent agenda batch motions (one motion covering multiple routine items), set agenda_item_ref to null.
        - For procedural motions (adjournment, minutes approval, recess), set agenda_item_ref to null.
        - When a motion clearly relates to one agenda item, reference that item.
        </agenda_item_ref_rules>

        <ambiguity_handling>
        - For "roll call" votes, list every member.
        - For "voice votes", leave "votes" empty unless exceptions are named.
        - Infer "yes" from "Present" members on unanimous votes ONLY if confident.
        </ambiguity_handling>

        Agenda Items:
        {{agenda_items}}

        Text:
        {{text}}
      PROMPT
    },
```

- [ ] **Step 2: Update the seed metadata placeholder list**

In `db/seeds/prompt_templates.rb`, find the `extract_votes` entry and add the `agenda_items` placeholder:

```ruby
  {
    key: "extract_votes",
    name: "Vote Extraction",
    description: "Extracts motions and vote records from meeting minutes",
    usage_context: "Meeting page: the motion text and pass/fail/tabled vote badges on each agenda item card",
    model_tier: "default",
    placeholders: [
      { "name" => "text", "description" => "Meeting minutes text (truncated to 50k chars)" },
      { "name" => "agenda_items", "description" => "Numbered agenda items for the meeting (for motion-to-item linking)" }
    ]
  },
```

- [ ] **Step 3: Populate the prompt in the database**

Run: `bin/rails prompt_templates:populate`

Expected: `Updated 'extract_votes'` in output. Verify with: `bin/rails runner "puts PromptTemplate.find_by!(key: 'extract_votes').instructions[0..100]"`

- [ ] **Step 4: Commit**

```bash
git add lib/prompt_template_data.rb db/seeds/prompt_templates.rb
git commit -m "feat(#76): add agenda_item_ref to extract_votes prompt template

Instructs AI to return an agenda_item_ref with each motion, referencing
the agenda item number/title. Adds agenda_items placeholder for passing
item context to the prompt."
```

---

### Task 2: Update OpenAiService to Accept Agenda Items

**Files:**
- Modify: `app/services/ai/open_ai_service.rb:36-74` — Add `agenda_items_text` keyword arg

- [ ] **Step 1: Update the `extract_votes` method signature**

In `app/services/ai/open_ai_service.rb`, find the `extract_votes` method (line 36) and change:

```ruby
    def extract_votes(text, source: nil)
```

to:

```ruby
    def extract_votes(text, agenda_items_text: "", source: nil)
```

- [ ] **Step 2: Add agenda_items to the placeholders hash**

In the same method, find:

```ruby
      placeholders = { text: text.truncate(50_000) }
```

Replace with:

```ruby
      placeholders = { text: text.truncate(50_000), agenda_items: agenda_items_text }
```

- [ ] **Step 3: Verify no tests break**

Run: `bin/rails test`

Expected: All existing tests pass. The new keyword arg defaults to `""` so callers that don't pass it continue to work.

- [ ] **Step 4: Commit**

```bash
git add app/services/ai/open_ai_service.rb
git commit -m "feat(#76): accept agenda_items_text in extract_votes

Passes agenda item context to the prompt template for motion-to-item
matching. Defaults to empty string for backward compatibility."
```

---

### Task 3: Add Agenda Item Resolution to ExtractVotesJob

**Files:**
- Modify: `app/jobs/extract_votes_job.rb` — Build agenda item context, resolve refs
- Create: `test/jobs/extract_votes_job_test.rb` — Full test coverage

- [ ] **Step 1: Write the test for agenda item matching by number**

Create `test/jobs/extract_votes_job_test.rb`:

```ruby
require "test_helper"
require "minitest/mock"

class ExtractVotesJobTest < ActiveJob::TestCase
  setup do
    @meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.ago, status: "parsed",
      detail_page_url: "http://example.com/m/votes-1"
    )
    @minutes_doc = MeetingDocument.create!(
      meeting: @meeting, document_type: "minutes_pdf",
      extracted_text: "Motion to approve lead service line contract. Passed 7-0."
    )
    @item_7a = AgendaItem.create!(
      meeting: @meeting, number: "7a",
      title: "Lead Service Line Replacement Program", order_index: 1
    )
    @item_7b = AgendaItem.create!(
      meeting: @meeting, number: "7b",
      title: "Street Repair Contract", order_index: 2
    )
  end

  test "links motion to agenda item by item number match" do
    ai_response = {
      "motions" => [ {
        "description" => "Approve lead service line contract",
        "outcome" => "passed",
        "agenda_item_ref" => "7a: Lead Service Line Replacement Program",
        "votes" => [ { "member" => "Ald. Smith", "value" => "yes" } ]
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      kwargs[:agenda_items_text].include?("7a:")
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motion = @meeting.motions.reload.first
    assert_equal @item_7a, motion.agenda_item
    mock_ai.verify
  end

  test "links motion to agenda item by title similarity when no number match" do
    item_no_number = AgendaItem.create!(
      meeting: @meeting, number: nil,
      title: "Waterfront Development Proposal", order_index: 3
    )

    ai_response = {
      "motions" => [ {
        "description" => "Approve waterfront development",
        "outcome" => "passed",
        "agenda_item_ref" => "Waterfront Development Proposal",
        "votes" => []
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motion = @meeting.motions.reload.first
    assert_equal item_no_number, motion.agenda_item
    mock_ai.verify
  end

  test "leaves agenda_item nil when ref is null" do
    ai_response = {
      "motions" => [ {
        "description" => "Motion to adjourn",
        "outcome" => "passed",
        "agenda_item_ref" => nil,
        "votes" => []
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motion = @meeting.motions.reload.first
    assert_nil motion.agenda_item_id
    mock_ai.verify
  end

  test "leaves agenda_item nil when ref does not match any item" do
    ai_response = {
      "motions" => [ {
        "description" => "Approve something unknown",
        "outcome" => "passed",
        "agenda_item_ref" => "99z: Nonexistent Item That Cannot Match",
        "votes" => []
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motion = @meeting.motions.reload.first
    assert_nil motion.agenda_item_id
    mock_ai.verify
  end

  test "passes agenda items text to AI service" do
    ai_response = { "motions" => [] }.to_json
    captured_kwargs = nil

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      captured_kwargs = kwargs
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    assert_includes captured_kwargs[:agenda_items_text], "7a: Lead Service Line Replacement Program"
    assert_includes captured_kwargs[:agenda_items_text], "7b: Street Repair Contract"
    mock_ai.verify
  end

  test "skips when no minutes text available" do
    @minutes_doc.destroy!

    assert_no_difference "Motion.count" do
      ExtractVotesJob.perform_now(@meeting.id)
    end
  end

  test "is idempotent — clears and rebuilds motions" do
    # Pre-existing motion
    Motion.create!(meeting: @meeting, description: "Old motion", outcome: "passed")

    ai_response = {
      "motions" => [ {
        "description" => "New motion",
        "outcome" => "passed",
        "agenda_item_ref" => nil,
        "votes" => []
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motions = @meeting.motions.reload
    assert_equal 1, motions.size
    assert_equal "New motion", motions.first.description
    mock_ai.verify
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/jobs/extract_votes_job_test.rb`

Expected: Tests fail — `extract_votes` is not called with `agenda_items_text`, and `resolve_agenda_item` doesn't exist yet.

- [ ] **Step 3: Implement the job changes**

Replace the full content of `app/jobs/extract_votes_job.rb`:

```ruby
class ExtractVotesJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    minutes_doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf")

    unless minutes_doc&.extracted_text.present?
      Rails.logger.info "No minutes text available for Meeting #{meeting_id}"
      return
    end

    agenda_items = meeting.agenda_items.to_a
    agenda_items_text = build_agenda_items_text(agenda_items)

    ai_service = ::Ai::OpenAiService.new
    json_response = ai_service.extract_votes(
      minutes_doc.extracted_text,
      agenda_items_text: agenda_items_text,
      source: meeting
    )

    begin
      data = JSON.parse(json_response)
      motions = data["motions"] || []

      ActiveRecord::Base.transaction do
        meeting.motions.destroy_all

        motions.each do |m_data|
          agenda_item = resolve_agenda_item(m_data["agenda_item_ref"], agenda_items)

          motion = meeting.motions.create!(
            description: m_data["description"],
            outcome: m_data["outcome"],
            agenda_item: agenda_item
          )

          m_data["votes"]&.each do |v_data|
            raw_name = v_data["member"]
            next if raw_name.blank?

            member = Member.resolve(raw_name)
            next unless member

            val = v_data["value"]&.downcase
            next if val.blank?
            val = "abstain" unless %w[yes no abstain absent recused].include?(val)

            Vote.create!(
              motion: motion,
              member: member,
              value: val
            )
          end
        end
      end

      Rails.logger.info "Extracted #{motions.size} motions for Meeting #{meeting_id}"
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse votes JSON for Meeting #{meeting_id}: #{e.message}"
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Validation error saving votes for Meeting #{meeting_id}: #{e.message}"
    end

    Topics::UpdateContinuityJob.perform_later(meeting_id: meeting_id)
  end

  private

  def build_agenda_items_text(agenda_items)
    agenda_items.map { |ai|
      ai.number.present? ? "#{ai.number}: #{ai.title}" : ai.title
    }.join("\n")
  end

  def resolve_agenda_item(ref, agenda_items)
    return nil if ref.blank?

    # Try matching by item number first
    number_match = ref.match(/\A(\S+?)[\s:]/i)
    if number_match
      candidate = number_match[1]
      by_number = agenda_items.find { |ai| ai.number&.downcase == candidate.downcase }
      return by_number if by_number
    end

    # Fall back to title similarity (word overlap)
    ref_words = ref.downcase.gsub(/[^a-z0-9\s]/, "").split
    return nil if ref_words.empty?

    best_match = nil
    best_score = 0.0

    agenda_items.each do |ai|
      next if ai.title.blank?
      item_words = ai.title.downcase.gsub(/[^a-z0-9\s]/, "").split
      next if item_words.empty?

      overlap = (ref_words & item_words).size
      score = overlap.to_f / [ ref_words.size, item_words.size ].max

      if score > best_score
        best_score = score
        best_match = ai
      end
    end

    best_score >= 0.5 ? best_match : nil
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/jobs/extract_votes_job_test.rb`

Expected: All 7 tests pass.

- [ ] **Step 5: Run the full test suite**

Run: `bin/rails test`

Expected: All tests pass. The changes are backward-compatible.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/extract_votes_job.rb test/jobs/extract_votes_job_test.rb
git commit -m "feat(#76): link motions to agenda items in ExtractVotesJob

AI returns agenda_item_ref per motion. Job resolves refs to real
AgendaItem records by item number (exact) then title similarity (fuzzy,
50% threshold). Unmatched motions keep agenda_item_id nil.

Closes #76"
```

---

## Phase 2: Record Enrichment + Meeting Links (#89)

### Task 4: Add Record Meeting Lookup to Controller

**Files:**
- Modify: `app/controllers/topics_controller.rb:44-63` — Add `@record_meetings` and `@typical_committee`

- [ ] **Step 1: Write the test for @record_meetings**

Add to `test/controllers/topics_controller_test.rb`:

```ruby
  test "show loads record_meetings for timeline linking" do
    appearance = TopicAppearance.create!(
      topic: @active_topic, meeting: @meeting,
      agenda_item: @agenda_item, appeared_at: @meeting.starts_at,
      evidence_type: "agenda_item"
    )

    get topic_url(@active_topic)
    assert_response :success
    # The view should render without error — record_meetings is loaded
  end
```

- [ ] **Step 2: Run the test to verify it passes (baseline)**

Run: `bin/rails test test/controllers/topics_controller_test.rb -n "/record_meetings/"`

Expected: PASS — the test just checks the page renders. We're establishing the baseline before adding the lookup.

- [ ] **Step 3: Add `@record_meetings` and `@typical_committee` to the controller**

In `app/controllers/topics_controller.rb`, in the `show` method, add after the `@decisions` query (before the `rescue`):

```ruby
    # Record enrichment: map (date, body_name) → TopicAppearance for linking
    @record_meetings = @topic.topic_appearances
                             .includes(meeting: :meeting_summaries, agenda_item: [])
                             .index_by { |a| "#{a.appeared_at.to_date}:#{a.meeting.body_name}" }

    # Coming Up fallback: most frequent committee for this topic
    @typical_committee = @topic.topic_appearances
                               .joins(:meeting)
                               .group("meetings.body_name")
                               .order(Arel.sql("COUNT(*) DESC"))
                               .limit(1)
                               .pick("meetings.body_name")
```

- [ ] **Step 4: Run the full controller test suite**

Run: `bin/rails test test/controllers/topics_controller_test.rb`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/topics_controller.rb test/controllers/topics_controller_test.rb
git commit -m "feat(#89): add record_meetings and typical_committee to topic show

Loads TopicAppearance lookup for Record timeline meeting links and
derives most frequent committee for Coming Up fallback."
```

---

### Task 5: Add Record Enrichment Helpers

**Files:**
- Modify: `app/helpers/topics_helper.rb` — Add `enrich_record_entry`, `extract_meeting_item_summary`
- Modify: `test/helpers/topics_helper_test.rb` — Test enrichment

- [ ] **Step 1: Write the tests**

Add to `test/helpers/topics_helper_test.rb`:

```ruby
  test "enrich_record_entry returns meeting when appearance found" do
    meeting = OpenStruct.new(id: 1, body_name: "City Council")
    appearance = OpenStruct.new(meeting: meeting, agenda_item: nil)
    record_meetings = { "2025-09-02:City Council" => appearance }

    entry = { "date" => "2025-09-02", "event" => "Council approved plan.", "meeting" => "City Council" }
    result = enrich_record_entry(entry, record_meetings)

    assert_equal "Council approved plan.", result[:event]
    assert_equal meeting, result[:meeting]
    assert_equal "City Council", result[:meeting_name]
  end

  test "enrich_record_entry returns nil meeting when no appearance found" do
    record_meetings = {}
    entry = { "date" => "2025-09-02", "event" => "Something happened.", "meeting" => "Unknown Board" }
    result = enrich_record_entry(entry, record_meetings)

    assert_nil result[:meeting]
    assert_equal "Unknown Board", result[:meeting_name]
  end

  test "enrich_record_entry replaces appeared on the agenda with item summary" do
    summary = MeetingSummary.new(
      generation_data: {
        "item_details" => [
          { "agenda_item_title" => "Lead Service Lines", "summary" => "Council approved $2.4M contract with Northern Pipe for replacement." }
        ]
      }
    )
    meeting = OpenStruct.new(id: 1, body_name: "City Council", meeting_summaries: [ summary ])
    agenda_item = OpenStruct.new(title: "Lead Service Lines")
    appearance = OpenStruct.new(meeting: meeting, agenda_item: agenda_item)
    record_meetings = { "2025-09-02:City Council" => appearance }

    entry = { "date" => "2025-09-02", "event" => "Appeared on the agenda.", "meeting" => "City Council" }
    result = enrich_record_entry(entry, record_meetings)

    assert_includes result[:event], "Council approved $2.4M contract"
  end

  test "enrich_record_entry falls back to agenda item title when no summary match" do
    meeting = OpenStruct.new(id: 1, body_name: "City Council", meeting_summaries: [])
    agenda_item = OpenStruct.new(title: "Lead Service Line Replacement Program")
    appearance = OpenStruct.new(meeting: meeting, agenda_item: agenda_item)
    record_meetings = { "2025-09-02:City Council" => appearance }

    entry = { "date" => "2025-09-02", "event" => "Appeared on the agenda.", "meeting" => "City Council" }
    result = enrich_record_entry(entry, record_meetings)

    assert_equal "Lead Service Line Replacement Program", result[:event]
  end

  test "enrich_record_entry keeps original event text when not appeared on the agenda" do
    meeting = OpenStruct.new(id: 1, body_name: "City Council", meeting_summaries: [])
    appearance = OpenStruct.new(meeting: meeting, agenda_item: nil)
    record_meetings = { "2025-09-02:City Council" => appearance }

    entry = { "date" => "2025-09-02", "event" => "Council voted 5-2 to approve.", "meeting" => "City Council" }
    result = enrich_record_entry(entry, record_meetings)

    assert_equal "Council voted 5-2 to approve.", result[:event]
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/helpers/topics_helper_test.rb -n "/enrich_record_entry/"`

Expected: FAIL — `enrich_record_entry` method not defined.

- [ ] **Step 3: Implement the helpers**

Add to `app/helpers/topics_helper.rb`, before the `private` section (or at the end of the module if no `private` keyword):

```ruby
  def enrich_record_entry(entry, record_meetings)
    key = "#{entry['date']}:#{entry['meeting']}"
    appearance = record_meetings[key]
    meeting = appearance&.meeting

    event_text = entry["event"]
    if event_text&.match?(/appeared on the agenda/i) && appearance
      enriched = extract_meeting_item_summary(meeting, appearance.agenda_item)
      event_text = enriched if enriched.present?
    end

    { event: event_text, meeting_name: entry["meeting"], meeting: meeting }
  end

  private

  def extract_meeting_item_summary(meeting, agenda_item)
    return agenda_item&.title unless meeting

    meeting.meeting_summaries.each do |summary|
      items = summary.generation_data&.dig("item_details")
      next unless items.is_a?(Array)

      target_title = agenda_item&.title&.downcase
      next unless target_title

      matched_item = items.find { |item|
        item_title = item["agenda_item_title"]&.downcase
        next false unless item_title
        item_title.include?(target_title) || target_title.include?(item_title)
      }

      return matched_item["summary"].truncate(200) if matched_item&.dig("summary").present?
    end

    agenda_item&.title
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/helpers/topics_helper_test.rb`

Expected: All tests pass (both old and new).

- [ ] **Step 5: Commit**

```bash
git add app/helpers/topics_helper.rb test/helpers/topics_helper_test.rb
git commit -m "feat(#89): add record enrichment helpers for topic timeline

enrich_record_entry cross-references factual_record entries with
MeetingSummary item_details to replace 'appeared on the agenda' with
actual content. Falls back to agenda item title."
```

---

### Task 6: Update Topic Show View for Record Links and Enrichment

**Files:**
- Modify: `app/views/topics/show.html.erb:137-158` — Use enrichment helper, render links

- [ ] **Step 1: Update the Record section in the view**

In `app/views/topics/show.html.erb`, replace the Record section (lines 137-158):

```erb
<%# === 6. Record (timeline) === %>
<section class="topic-record section topic-section">
  <h2 class="section-title">Record</h2>
  <% record_entries = briefing_factual_record(@briefing) %>
  <% if record_entries.any? %>
    <div class="topic-timeline">
      <% record_entries.each do |entry| %>
        <% enriched = enrich_record_entry(entry, @record_meetings || {}) %>
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
    </div>
  <% else %>
    <p class="section-empty">No meeting activity recorded for this topic yet.</p>
  <% end %>
</section>
```

- [ ] **Step 2: Run the controller tests to verify the view renders**

Run: `bin/rails test test/controllers/topics_controller_test.rb`

Expected: All tests pass. The `@record_meetings || {}` fallback ensures old tests without the variable still work.

- [ ] **Step 3: Commit**

```bash
git add app/views/topics/show.html.erb
git commit -m "feat(#89): render Record timeline with meeting links and enriched text

Meeting names link to meeting pages. 'Appeared on the agenda' entries
are replaced with MeetingSummary item_details or agenda item titles.

Closes #89"
```

---

## Phase 3: Visual/UX Overhaul (#63)

### Task 7: Adaptive Section Visibility

**Files:**
- Modify: `app/views/topics/show.html.erb` — Hide empty sections, add Coming Up fallback
- Modify: `test/controllers/topics_controller_test.rb` — Update visibility tests

- [ ] **Step 1: Update tests for new section visibility behavior**

In `test/controllers/topics_controller_test.rb`, find and replace the existing empty-state tests:

Replace `test "show always renders all six sections"`:

```ruby
  test "show hides sections with no data instead of showing empty state" do
    get topic_url(@active_topic)
    assert_response :success
    # What to Watch: hidden when no briefing
    assert_select ".topic-watch", 0
    # Coming Up: shows fallback or hidden
    # Key Decisions: hidden when no motions
    assert_select ".topic-decisions", 0
    # Story: hidden when no briefing
    assert_select ".topic-story", 0
    # Record: hidden when no generation_data
    assert_select ".topic-record .section-empty", text: /No meeting activity/
  end
```

Replace `test "show displays empty state for what to watch when no briefing"`:

```ruby
  test "show hides what to watch when no briefing" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-watch", 0
  end
```

Replace `test "show displays empty state for coming up when no future meetings"`:

```ruby
  test "show shows typical committee fallback when no upcoming meetings" do
    # Create a past appearance so typical_committee is derived
    TopicAppearance.create!(
      topic: @active_topic, meeting: @meeting,
      appeared_at: @meeting.starts_at,
      evidence_type: "agenda_item"
    )

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-coming-up-fallback", text: /typically discussed at/i
  end
```

Replace `test "show displays empty state for story when no briefing"`:

```ruby
  test "show hides story when no briefing" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-story", 0
  end
```

Replace `test "show displays empty state for key decisions when no motions"`:

```ruby
  test "show hides key decisions when no motions" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-decisions", 0
  end
```

Keep `test "show displays empty state for record when no generation data"` as-is (Record always shows).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/topics_controller_test.rb -n "/show hides|show shows typical/"`

Expected: FAIL — sections still render with empty states.

- [ ] **Step 3: Update the view with adaptive section visibility**

Replace the full content of `app/views/topics/show.html.erb`:

```erb
<% content_for(:title) { "#{@topic.name} - Topics - Two Rivers Matters" } %>

<%# === 1. Header (always present) === %>
<div class="page-header">
  <h1 class="page-title"><%= @topic.name %></h1>
  <% if @topic.description.present? %>
    <p class="page-subtitle"><%= @topic.description %></p>
  <% end %>
  <div class="flex items-center gap-2 mt-2">
    <% if @topic.lifecycle_status %>
      <%= topic_lifecycle_badge(@topic.lifecycle_status) %>
    <% end %>
    <% if @briefing %>
      <%= briefing_freshness_badge(@briefing) %>
    <% end %>
  </div>
</div>

<%# === 2. What to Watch (warm callout) — hidden when no data === %>
<% watch_text = briefing_what_to_watch(@briefing) %>
<% if watch_text.present? %>
  <section class="topic-watch section">
    <h2 class="section-title">What to Watch</h2>
    <div class="topic-watch-callout">
      <p><%= render_inline_markdown(watch_text) %></p>
    </div>
  </section>
  <%= render "shared/diamond_divider" %>
<% end %>

<%# === 3. Coming Up (meeting cards or fallback) === %>
<% if @upcoming.any? %>
  <section class="topic-upcoming section topic-section">
    <h2 class="section-title">Coming Up</h2>
    <div class="card-grid">
      <% @upcoming.each do |appearance| %>
        <% is_council = appearance.meeting.body_name.include?("Council") && !appearance.meeting.body_name.include?("Work Session") %>
        <%= link_to meeting_path(appearance.meeting), class: "card card-link card-link--upcoming" do %>
          <div class="date-slab <%= 'council' if is_council %>">
            <span class="date-month"><%= appearance.meeting.starts_at.strftime("%b") %></span>
            <span class="date-day"><%= appearance.meeting.starts_at.strftime("%-d") %></span>
          </div>
          <div class="card-body">
            <div class="text-sm text-secondary mb-1">
              <%= appearance.meeting.body_name %>
            </div>
            <% if appearance.meeting.location.present? %>
              <div class="text-sm text-secondary mb-2">
                <%= appearance.meeting.location %>
              </div>
            <% end %>
            <% if appearance.agenda_item %>
              <div class="mb-2">
                <%= appearance.agenda_item.title %>
              </div>
              <% if public_comment_meeting?(appearance.agenda_item) %>
                <span class="badge badge--info mb-2">Public comment period</span>
              <% end %>
            <% end %>
            <div class="mt-3">
              <span class="btn btn--secondary btn--sm">View meeting →</span>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
  </section>
  <%= render "shared/diamond_divider" %>
<% elsif @typical_committee.present? %>
  <section class="topic-upcoming section topic-section">
    <h2 class="section-title">Coming Up</h2>
    <p class="topic-coming-up-fallback">
      This topic is typically discussed at <strong><%= @typical_committee %></strong>.
      Check back when the next agenda is published.
    </p>
  </section>
  <%= render "shared/diamond_divider" %>
<% end %>

<%# === 4. The Story (editorial) — hidden when no data === %>
<% story_text = briefing_current_state(@briefing) %>
<% if story_text.present? %>
  <section class="topic-story section topic-section">
    <h2 class="section-title">The Story</h2>
    <div class="card">
      <div class="card-body briefing-editorial-content">
        <%= sanitize(render_briefing_editorial(story_text)) %>
      </div>
    </div>
    <% concerns = briefing_process_concerns(@briefing) %>
    <% if concerns.any? %>
      <div class="topic-concerns-callout">
        <div class="concerns-label">Worth noting</div>
        <ul>
          <% concerns.each do |concern| %>
            <li><%= concern %></li>
          <% end %>
        </ul>
      </div>
    <% end %>
  </section>
  <%= render "shared/diamond_divider" %>
<% end %>

<%# === 5. Key Decisions (votes) — hidden when no linked motions === %>
<% if @decisions.any? %>
  <section class="topic-decisions section topic-section">
    <h2 class="section-title">Key Decisions</h2>
    <% @decisions.each do |motion| %>
      <div class="topic-decision-item">
        <div class="flex justify-between items-center mb-1">
          <span class="decision-badge <%= decision_badge_class(motion.outcome) %>">
            <%= motion_outcome_text(motion) %>
          </span>
          <span class="topic-decision-meeting-ref">
            <%= link_to motion.meeting.body_name, meeting_path(motion.meeting) %>,
            <%= motion.meeting.starts_at.strftime("%B %-d, %Y") %>
          </span>
        </div>
        <div class="mb-2"><%= motion.description %></div>
        <% if motion.votes.any? %>
          <div class="votes-label text-sm font-medium text-secondary">How they voted</div>
          <div class="votes-grid">
            <% motion.votes.each do |vote| %>
              <div class="vote-card vote-card--<%= vote.value %> text-sm">
                <span class="font-bold"><%= vote.member.name %></span>
                <span class="vote-value--<%= vote.value %>"><%= vote.value.titleize %></span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    <% end %>
  </section>
  <%= render "shared/diamond_divider" %>
<% end %>

<%# === 6. Record (timeline) — always shown === %>
<section class="topic-record section topic-section">
  <h2 class="section-title">Record</h2>
  <% record_entries = briefing_factual_record(@briefing) %>
  <% if record_entries.any? %>
    <div class="topic-timeline">
      <% record_entries.each do |entry| %>
        <% enriched = enrich_record_entry(entry, @record_meetings || {}) %>
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
    </div>
  <% else %>
    <p class="section-empty">No meeting activity recorded for this topic yet.</p>
  <% end %>
</section>

<%# === Footer === %>
<div class="mt-8">
  <%= link_to "← Back to Topics", topics_path, class: "btn btn--secondary" %>
</div>
```

- [ ] **Step 4: Run all controller tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb`

Expected: All tests pass. Some old tests may need adjustment if they asserted specific empty state text that's now hidden — fix inline.

- [ ] **Step 5: Commit**

```bash
git add app/views/topics/show.html.erb test/controllers/topics_controller_test.rb
git commit -m "feat(#63): adaptive section visibility on topic show page

Hide What to Watch, Story, and Key Decisions when no data. Coming Up
shows 'typically discussed at [committee]' fallback. Diamond dividers
between sections. Key Decisions uses decision badges from meeting show."
```

---

### Task 8: CSS Affordances and Visual Hierarchy

**Files:**
- Modify: `app/assets/stylesheets/application.css` — Add affordance styles, new CSS classes

- [ ] **Step 1: Add the new CSS**

Find the topic section styles in `app/assets/stylesheets/application.css` (look for `.topic-watch` or `.topic-timeline`). Add the following new rules in that area:

```css
/* === Topic page affordances === */

/* Links in topic content should be clearly clickable */
.topic-timeline-meeting-link {
  color: var(--color-primary);
  text-decoration: underline;
  text-decoration-color: var(--color-border);
  text-underline-offset: 2px;
}

.topic-timeline-meeting-link:hover {
  text-decoration-color: var(--color-primary);
  color: var(--color-text);
}

/* Card hover states */
.card-link--upcoming {
  display: flex;
  gap: 1rem;
  align-items: flex-start;
  transition: box-shadow 0.15s ease, transform 0.15s ease;
}

.card-link--upcoming:hover {
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
  transform: translateY(-1px);
}

/* Date slab for Coming Up (reuse from homepage) */
.topic-upcoming .date-slab {
  min-width: 60px;
  text-align: center;
  padding: 0.5rem;
  background: var(--color-primary);
  color: var(--color-bg);
  border-radius: 4px;
  flex-shrink: 0;
}

.topic-upcoming .date-slab.council {
  background: var(--color-terra-cotta);
}

.topic-upcoming .date-month {
  display: block;
  font-family: var(--font-data);
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.topic-upcoming .date-day {
  display: block;
  font-family: var(--font-display);
  font-size: 1.5rem;
  font-weight: 700;
  line-height: 1;
}

/* Coming Up fallback text */
.topic-coming-up-fallback {
  color: var(--color-text-secondary);
  font-style: italic;
}

/* Key Decisions: meeting reference link */
.topic-decision-meeting-ref {
  font-family: var(--font-data);
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--color-text-secondary);
}

.topic-decision-meeting-ref a {
  color: var(--color-text-secondary);
  text-decoration: underline;
  text-decoration-color: var(--color-border);
  text-underline-offset: 2px;
}

.topic-decision-meeting-ref a:hover {
  color: var(--color-primary);
  text-decoration-color: var(--color-primary);
}

/* Section titles — consistent Outfit uppercase treatment */
.topic-section .section-title {
  font-family: var(--font-display);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  padding-bottom: 0.5rem;
  border-bottom: 2px solid var(--color-primary);
  display: inline-block;
  margin-bottom: 1.5rem;
}
```

- [ ] **Step 2: Verify the CSS renders correctly**

Run: `bin/dev` and visit a topic page in the browser. Check:
- Record meeting names are underlined links
- Coming Up cards have date slabs and hover elevation
- Section titles are Outfit uppercase with accent border
- Diamond dividers appear between sections

- [ ] **Step 3: Run lint**

Run: `bin/rubocop`

Expected: No new violations (CSS changes don't trigger RuboCop).

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "feat(#63): add affordance CSS for topic page overhaul

Link underlines, card hover states, date slabs for Coming Up, decision
meeting refs, consistent section title treatment.

Closes #63"
```

---

### Task 9: Final Verification and Documentation

**Files:**
- Modify: `CLAUDE.md` — Update Known Issues section

- [ ] **Step 1: Run the full test suite**

Run: `bin/rails test`

Expected: All tests pass.

- [ ] **Step 2: Run CI checks**

Run: `bin/ci`

Expected: Clean pass.

- [ ] **Step 3: Update CLAUDE.md Known Issues**

In `CLAUDE.md`, find the "Known issues (Apr 2026):" section under "### Topic Show Page" and replace it:

```markdown
**Resolved issues (Apr 2026):**
- **Key Decisions populated** — `ExtractVotesJob` now links motions to agenda items via `agenda_item_ref`. Backfill needed for existing meetings.
- **Record entries enriched** — view-layer enrichment replaces "appeared on the agenda" with MeetingSummary item_details. Meeting names are links.
- **Adaptive empty states** — Key Decisions hidden when empty. Coming Up shows "typically discussed at [committee]" fallback.

**Remaining issues:**
- **Coming Up empty most of the time** — agendas not published far in advance. Fallback shows typical committee, but no scheduled date.
- **Overall UX**: #63 visual work shipped; homepage link targets still go to meetings until topic pages prove out.
```

- [ ] **Step 4: Commit documentation**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for topic page overhaul (#63, #76, #89)"
```

---

## Backfill (Post-Deploy)

After all phases are deployed, run this to populate `agenda_item_id` on existing motions:

```bash
bin/rails runner "Meeting.joins(:meeting_documents).where(meeting_documents: { document_type: 'minutes_pdf' }).find_each { |m| ExtractVotesJob.perform_later(m.id) }"
```

Or in production:
```bash
bin/kamal app exec "bin/rails runner \"Meeting.joins(:meeting_documents).where(meeting_documents: { document_type: 'minutes_pdf' }).find_each { |m| ExtractVotesJob.perform_later(m.id) }\""
```

Monitor via Solid Queue job runs in admin dashboard.
