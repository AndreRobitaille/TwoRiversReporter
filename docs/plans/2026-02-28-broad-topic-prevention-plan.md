# Broad Topic Prevention Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent overly-broad "process category" topics (like "zoning") from being created by the extraction pipeline, and selectively re-extract existing broad topics into specific civic concerns.

**Architecture:** Three changes: (1) add a `<topic_granularity>` section to the extraction prompt that forbids category names as topic tags, (2) seed the existing `TopicBlocklist` with category names as a safety net, (3) a rake task to re-extract agenda items from a named broad topic. No schema changes. No new models.

**Tech Stack:** Rails 8.1, Minitest, OpenAI API via `Ai::OpenAiService`, existing `TopicBlocklist` model, existing `Topics::FindOrCreateService`.

**Design doc:** `docs/plans/2026-02-28-broad-topic-prevention-design.md`

---

### Task 1: Add `<topic_granularity>` to extraction prompt

**Files:**
- Modify: `app/services/ai/open_ai_service.rb:112-142`
- Test: `test/jobs/extract_topics_job_test.rb`

**Step 1: Write the failing test**

Add a test to `test/jobs/extract_topics_job_test.rb` that verifies the extraction prompt contains granularity instructions. The test captures the prompt text sent to the AI and checks for the granularity section.

```ruby
test "extraction prompt includes topic granularity instructions" do
  meeting = Meeting.create!(
    body_name: "City Council", meeting_type: "Regular",
    starts_at: 1.day.from_now, status: "agenda_posted",
    detail_page_url: "http://example.com/m/granularity"
  )
  AgendaItem.create!(meeting: meeting, number: "1", title: "Test Item", order_index: 1)

  captured_text = nil
  ai_response = {
    "items" => [ {
      "id" => 999, "category" => "Other",
      "tags" => [], "topic_worthy" => false, "confidence" => 0.5
    } ]
  }.to_json

  mock_ai = Minitest::Mock.new
  mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
    captured_text = text
    true
  end

  retrieval_stub = Object.new
  def retrieval_stub.retrieve_context(*args, **kwargs); []; end
  def retrieval_stub.format_context(*args); ""; end

  RetrievalService.stub :new, retrieval_stub do
    Ai::OpenAiService.stub :new, mock_ai do
      ExtractTopicsJob.perform_now(meeting.id)
    end
  end

  # The prompt is assembled inside OpenAiService, not ExtractTopicsJob.
  # So instead, verify the prompt content via a direct service test.
  mock_ai.verify
end
```

Actually — the prompt is built inside `OpenAiService#extract_topics`, not in the job. The better test is a direct service test that verifies the prompt content. Add this test to a new file.

Create: `test/services/ai/open_ai_service_extract_topics_test.rb`

```ruby
require "test_helper"

class Ai::OpenAiServiceExtractTopicsTest < ActiveSupport::TestCase
  setup do
    @service = Ai::OpenAiService.new
    @mock_client = Minitest::Mock.new
    @service.instance_variable_set(:@client, @mock_client)
  end

  test "prompt forbids category names as topic tags" do
    captured_prompt = nil
    mock_response = {
      "choices" => [{ "message" => { "content" => '{"items":[]}' } }]
    }

    @mock_client.expect :chat, mock_response do |params:|
      captured_prompt = params[:messages].last[:content]
      true
    end

    @service.extract_topics("ID: 1\nTitle: Test")

    assert_includes captured_prompt, "topic_granularity"
    assert_includes captured_prompt, "NEVER use a category name as a topic tag"
    @mock_client.verify
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/ai/open_ai_service_extract_topics_test.rb -v`
Expected: FAIL — prompt does not yet contain "topic_granularity" or "NEVER use a category name"

**Step 3: Write the implementation**

In `app/services/ai/open_ai_service.rb`, add a `<topic_granularity>` block inside the `extract_topics` prompt. Insert it between the `</governance_constraints>` line (after line 109) and the `#{existing_topics_text}` interpolation (line 110).

Add this block after line 109 (`</governance_constraints>`):

```ruby
        <topic_granularity>
        Category names (Infrastructure, Public Safety, Parks & Rec, Finance, Zoning,
        Licensing, Personnel, Governance) describe process DOMAINS, not topics.

        NEVER use a category name as a topic tag. The "category" field already captures
        the domain. The "tags" array must name the SPECIFIC civic concern.

        Good topic names (specific enough to tell a coherent story over time):
        - "conditional use permits" (recurring zoning process residents track)
        - "fence setback rules" (specific ordinance change affecting homeowners)
        - "downtown redevelopment" (ongoing planning effort)
        - "bus route subsidy" (specific budget/service issue)

        Bad topic names (too broad — contain dozens of unrelated concerns):
        - "zoning" (covers CUPs, variances, rezoning, ordinances, land sales)
        - "infrastructure" (covers roads, sewers, water, buildings)
        - "finance" (covers budgets, borrowing, grants, fees)

        Not topic-worthy (set topic_worthy: false):
        - One-off procedural actions (a single plat review, routine survey map)
        - Standard approvals with no controversy or recurring significance
        - Items that happen once and are done

        Ask yourself: "Would a resident follow this topic across multiple meetings?"
        If the answer only makes sense for a SPECIFIC concern within the category,
        name that concern. If the item is routine, mark it not topic-worthy.
        </topic_granularity>
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/ai/open_ai_service_extract_topics_test.rb -v`
Expected: PASS

**Step 5: Run full test suite for regressions**

Run: `bin/rails test`
Expected: All tests pass (existing extraction tests still work since the prompt change is additive)

**Step 6: Commit**

```bash
git add app/services/ai/open_ai_service.rb test/services/ai/open_ai_service_extract_topics_test.rb
git commit -m "feat: add topic granularity rules to extraction prompt

Instructs the AI to never use category names (Zoning, Infrastructure,
etc.) as topic tags. Categories describe domains; tags must name the
specific civic concern."
```

---

### Task 2: Seed category names into TopicBlocklist

**Files:**
- Modify: `lib/tasks/topics.rake`
- Test: `test/tasks/topics_rake_test.rb` (create)

**Step 1: Write the failing test**

Create: `test/tasks/topics_rake_test.rb`

```ruby
require "test_helper"

class TopicsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("topics:seed_category_blocklist")
  end

  test "seed_category_blocklist adds category names to blocklist" do
    TopicBlocklist.where(name: "zoning").destroy_all

    Rake::Task["topics:seed_category_blocklist"].invoke

    assert TopicBlocklist.where(name: "zoning").exists?, "zoning should be blocked"
    assert TopicBlocklist.where(name: "infrastructure").exists?, "infrastructure should be blocked"
    assert TopicBlocklist.where(name: "finance").exists?, "finance should be blocked"
  ensure
    Rake::Task["topics:seed_category_blocklist"].reenable
  end

  test "seed_category_blocklist is idempotent" do
    TopicBlocklist.where(name: "zoning").destroy_all

    Rake::Task["topics:seed_category_blocklist"].invoke
    count_after_first = TopicBlocklist.count
    Rake::Task["topics:seed_category_blocklist"].reenable
    Rake::Task["topics:seed_category_blocklist"].invoke
    count_after_second = TopicBlocklist.count

    assert_equal count_after_first, count_after_second
  ensure
    Rake::Task["topics:seed_category_blocklist"].reenable
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/tasks/topics_rake_test.rb -v`
Expected: FAIL — task does not exist

**Step 3: Write the implementation**

Add to `lib/tasks/topics.rake`, inside the `namespace :topics` block:

```ruby
  desc "Add process-category names to topic blocklist (idempotent)"
  task seed_category_blocklist: :environment do
    categories = [
      "zoning",
      "infrastructure",
      "public safety",
      "parks  rec",       # TopicBlocklist normalizes punctuation away
      "finance",
      "licensing",
      "personnel",
      "governance"
    ]

    categories.each do |name|
      entry = TopicBlocklist.find_or_initialize_by(name: name)
      if entry.new_record?
        entry.reason = "Process category — too broad for a topic"
        entry.save!
        puts "Added to blocklist: #{name}"
      else
        puts "Already blocked: #{name}"
      end
    end
  end
```

Note: `TopicBlocklist` normalizes names on `before_validation` (strips, lowercases, removes punctuation, squishes). So "parks & rec" becomes "parks rec" after normalization. Use the normalized form in the seed list since `find_or_initialize_by` will match the stored normalized value.

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/tasks/topics_rake_test.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/tasks/topics.rake test/tasks/topics_rake_test.rb
git commit -m "feat: add rake task to seed category names into topic blocklist

Adds zoning, infrastructure, public safety, parks & rec, finance,
licensing, personnel, and governance as blocked topic names."
```

---

### Task 3: Run the blocklist seed task

**Step 1: Run the seed task against the real database**

Run: `bin/rails topics:seed_category_blocklist`
Expected: Output showing which names were added vs. already blocked

**Step 2: Verify the blocklist contains the new entries**

Run: `bin/rails runner "TopicBlocklist.where(name: %w[zoning infrastructure finance]).pluck(:name, :reason).each { |n, r| puts \"#{n}: #{r}\" }"`
Expected: All three show up with the reason "Process category — too broad for a topic"

**Step 3: Verify FindOrCreateService rejects blocked categories**

Run: `bin/rails runner "puts Topics::FindOrCreateService.call('zoning').inspect"`
Expected: `nil` (blocked by TopicBlocklist)

**Step 4: Commit (no code changes — just record that the seed was run)**

No commit needed. The seed task is idempotent and the data is in the database.

---

### Task 4: Build the `topics:split_broad_topic` rake task

**Files:**
- Modify: `lib/tasks/topics.rake`
- Modify: `app/services/ai/open_ai_service.rb` (add `re_extract_item_topics` method)
- Test: `test/services/ai/open_ai_service_extract_topics_test.rb` (extend)
- Test: `test/tasks/topics_rake_test.rb` (extend)

**Step 1: Write the failing test for the new AI service method**

Add to `test/services/ai/open_ai_service_extract_topics_test.rb`:

```ruby
test "re_extract_item_topics returns tags and topic_worthy for a single item" do
  captured_prompt = nil
  mock_response = {
    "choices" => [{ "message" => { "content" => '{"tags":["fence setback rules"],"topic_worthy":true}' } }]
  }

  @mock_client.expect :chat, mock_response do |params:|
    captured_prompt = params[:messages].last[:content]
    true
  end

  result = @service.re_extract_item_topics(
    item_title: "Ordinance to amend fence height requirements",
    item_summary: nil,
    document_text: "Amending Section 10-1-15 to regulate fences in front yards",
    broad_topic_name: "zoning",
    existing_topics: ["conditional use permits", "downtown redevelopment"]
  )

  parsed = JSON.parse(result)
  assert parsed.key?("tags")
  assert parsed.key?("topic_worthy")
  assert_includes captured_prompt, "zoning"
  assert_includes captured_prompt, "conditional use permits"
  @mock_client.verify
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/ai/open_ai_service_extract_topics_test.rb -v`
Expected: FAIL — `re_extract_item_topics` method does not exist

**Step 3: Implement `re_extract_item_topics` in OpenAiService**

Add to `app/services/ai/open_ai_service.rb`, after the `refine_catchall_topic` method (after line ~200):

```ruby
    def re_extract_item_topics(item_title:, item_summary:, document_text:, broad_topic_name:, existing_topics: [])
      existing_topics_text = if existing_topics.any?
        "Existing topics (prefer reusing these when appropriate): #{existing_topics.join(', ')}"
      else
        ""
      end

      prompt = <<~PROMPT
        An agenda item was tagged with "#{broad_topic_name}", which is too broad to be
        a useful topic. It's a process category, not a specific civic concern.

        Re-classify this item. Return JSON with:
        - "tags": array of specific topic names (0-2 tags), or empty if not topic-worthy
        - "topic_worthy": true if this represents a persistent civic concern residents
          would follow across meetings, false if it's routine/one-off

        Agenda item title: #{item_title}
        #{item_summary.present? ? "Summary: #{item_summary}" : ""}

        Document text:
        #{document_text.to_s.truncate(6000, separator: ' ')}

        #{existing_topics_text}

        Topic names should be at a "neighborhood conversation" level:
        - Good: "conditional use permits", "fence setback rules", "downtown redevelopment"
        - Bad: "zoning" (too broad), "123 Main St fence variance" (too narrow)
        - If this is a routine one-off action, set topic_worthy to false and tags to []

        Return JSON: {"tags": [...], "topic_worthy": true/false}
      PROMPT

      response = @client.chat(
        parameters: {
          model: DEFAULT_MODEL,
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: "You are a civic data classifier for Two Rivers, WI." },
            { role: "user", content: prompt }
          ],
          temperature: 0.1
        }
      )
      response.dig("choices", 0, "message", "content")
    end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/ai/open_ai_service_extract_topics_test.rb -v`
Expected: PASS

**Step 5: Commit the service method**

```bash
git add app/services/ai/open_ai_service.rb test/services/ai/open_ai_service_extract_topics_test.rb
git commit -m "feat: add re_extract_item_topics method to OpenAiService

Re-classifies an agenda item away from a broad category topic into
specific civic concerns, or marks it not topic-worthy."
```

**Step 6: Implement the rake task**

Add to `lib/tasks/topics.rake`, inside the `namespace :topics` block:

```ruby
  desc "Re-extract items from a broad topic into specific topics"
  task :split_broad_topic, [:topic_name] => :environment do |_t, args|
    topic_name = args[:topic_name]
    abort "Usage: bin/rails topics:split_broad_topic[topic_name]" if topic_name.blank?

    normalized = Topic.normalize_name(topic_name)
    topic = Topic.find_by("LOWER(name) = ?", normalized)
    abort "Topic '#{topic_name}' not found" unless topic

    links = AgendaItemTopic.where(topic: topic).includes(agenda_item: { meeting: {}, meeting_documents: {} })
    puts "Found #{links.count} agenda items linked to '#{topic.name}'"
    abort "No items to re-extract" if links.empty?

    ai_service = Ai::OpenAiService.new
    existing_topics = Topic.approved.where.not(id: topic.id).pluck(:name)

    removed = 0
    retagged = 0
    skipped = 0

    links.find_each do |link|
      item = link.agenda_item
      meeting = item.meeting

      # Gather document context
      doc_parts = []
      item.meeting_documents.each do |doc|
        next if doc.extracted_text.blank?
        doc_parts << doc.extracted_text.truncate(2000, separator: " ")
      end
      meeting.meeting_documents.where(document_type: %w[packet_pdf minutes_pdf]).each do |doc|
        next if doc.extracted_text.blank?
        doc_parts << doc.extracted_text.truncate(4000, separator: " ")
      end
      doc_text = doc_parts.join("\n---\n")

      print "[#{meeting.starts_at&.strftime('%Y-%m-%d')} #{meeting.body_name}] #{item.title.truncate(60)}... "

      begin
        result = ai_service.re_extract_item_topics(
          item_title: item.title,
          item_summary: item.summary,
          document_text: doc_text,
          broad_topic_name: topic.name,
          existing_topics: existing_topics
        )

        data = JSON.parse(result)
        tags = data["tags"] || []
        topic_worthy = data.fetch("topic_worthy", false)

        if !topic_worthy || tags.empty?
          link.destroy!
          removed += 1
          puts "NOT TOPIC-WORTHY (removed)"
        else
          # Create new topic links, then remove old one
          tags.each do |new_name|
            new_topic = Topics::FindOrCreateService.call(new_name)
            if new_topic
              AgendaItemTopic.find_or_create_by!(agenda_item: item, topic: new_topic)
              puts "-> #{new_topic.name}"
              # Add to existing_topics so future items can reuse
              existing_topics << new_topic.name unless existing_topics.include?(new_topic.name)
            else
              puts "-> #{new_name} (BLOCKED)"
            end
          end
          link.destroy!
          retagged += 1
        end
      rescue JSON::ParserError, Faraday::Error => e
        puts "ERROR: #{e.class} #{e.message}"
        skipped += 1
      end
    end

    puts "\nDone. Removed: #{removed}, Retagged: #{retagged}, Errors: #{skipped}"
    remaining = AgendaItemTopic.where(topic: topic).count
    puts "#{remaining} items still linked to '#{topic.name}'"
  end
```

**Step 7: Run the full test suite**

Run: `bin/rails test`
Expected: All tests pass

**Step 8: Commit**

```bash
git add lib/tasks/topics.rake
git commit -m "feat: add topics:split_broad_topic rake task

Re-extracts agenda items from a named broad topic into specific
civic concerns. Items can be retagged or marked not topic-worthy."
```

---

### Task 5: Run re-extraction against "zoning" topic

**Step 1: Dry-run sanity check — see what we're working with**

Run: `bin/rails runner "t = Topic.find_by(canonical_name: 'zoning'); puts \"#{t.name}: #{AgendaItemTopic.where(topic: t).count} items\""`
Expected: `zoning: 26 items`

**Step 2: Run the split task**

Run: `bin/rails topics:split_broad_topic[zoning]`
Expected: Each item prints its result (retagged or removed). The task uses the real AI, so this will make ~26 API calls.

**Step 3: Verify results**

Run: `bin/rails runner "AgendaItemTopic.where(topic: Topic.find_by(canonical_name: 'zoning')).count.then { |c| puts \"Remaining: #{c}\" }; Topic.where(status: 'proposed').order(created_at: :desc).limit(10).each { |t| puts \"  NEW: #{t.name} (#{t.topic_appearances.count} appearances)\" }"`
Expected: 0 items remaining on "zoning". Some new proposed topics listed.

**Step 4: Review output and decide next steps**

- Look at the new proposed topics — do the names make sense?
- Run auto-triage if needed: `bin/rails runner "Topics::AutoTriageJob.perform_now"`
- Check if any new topics overlap with existing approved topics (triage should catch this)

No commit — this is a data operation, not a code change.

---

### Task 6: Update documentation

**Files:**
- Modify: `docs/plans/2026-02-28-broad-topic-prevention-design.md` (mark completed)
- Modify: `docs/topic-first-migration-plan.md` (update Phase 5 status)
- Modify: `CLAUDE.md` (add note about topic granularity)

**Step 1: Update CLAUDE.md**

Add to the "Conventions" section of `CLAUDE.md`:

```markdown
- **Topic granularity** — Category names (Zoning, Infrastructure, Finance, etc.) are blocked as topic names. Topics must name specific civic concerns at a "neighborhood conversation" level. See `docs/plans/2026-02-28-broad-topic-prevention-design.md`.
```

**Step 2: Update the migration plan**

In `docs/topic-first-migration-plan.md`, add a note under Phase 5 item 7 indicating that the broad-topic quality issue is addressed by this work.

**Step 3: Commit**

```bash
git add CLAUDE.md docs/topic-first-migration-plan.md docs/plans/2026-02-28-broad-topic-prevention-design.md
git commit -m "docs: update documentation for broad topic prevention"
```
