# Per-Meeting TopicSummary Item-Details Plumbing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `analyze_topic_summary` context starvation (issue #94) by plumbing `MeetingSummary.generation_data["item_details"]` into `Topics::SummaryContextBuilder#agenda_items_data`, so per-meeting `TopicSummary` rows name specific incidents instead of "agenda includes an item titled …" boilerplate.

**Architecture:** Mirrors the #93 fix pattern at a different layer. #93 plumbed `recent_item_details` into the briefing job (`analyze_topic_briefing`). This plan plumbs the same content into the per-meeting topic digest job (`analyze_topic_summary`). The `analyze_topic_summary` prompt sees a per-item JSON structure (one entry per linked agenda item), so the fix adds new fields **inside** each agenda_items entry rather than a new top-level context key. Reuses `Topics::TitleNormalizer` from #93 — no new service class needed.

**Tech Stack:** Rails 8.1, Ruby 4.0, Minitest, Kamal 2.

**Reference:** GitHub issue #94. Parent fix: #93. Discovered while diagnosing topic 513's briefing after #93 shipped.

---

## File Structure

**Modify:**
- `app/services/topics/summary_context_builder.rb` — `agenda_items_data` (~lines 34-88). Fetch the meeting's latest MeetingSummary once, build a normalized-title → item_details entry hash, and merge matched content into each per-item output.
- `test/services/topics/summary_context_builder_test.rb` — add 3 tests covering the new field population.
- `lib/prompt_template_data.rb` — `"analyze_topic_summary"` entry (~lines 451-559). Add a `<data_sources>` block between `</tone_calibration>` and `{{committee_context}}` telling the AI about the new per-item fields.

**Not touched:**
- `app/services/topics/recent_item_details_builder.rb` — separate consumer, works differently (flat list across meetings). Keep as-is.
- `app/jobs/summarize_meeting_job.rb` — read-only. The call site `generate_topic_summaries` already calls `SummaryContextBuilder.new(topic, meeting).build_context_json(...)`, so changes inside the builder flow through automatically.
- `app/jobs/topics/generate_topic_briefing_job.rb` — separate consumer, uses `SummaryContextBuilder` but only pulls `:agenda_items` from it for `recent_raw_context`. The new per-item keys will transparently show up there too, which is a bonus — briefing's `recent_raw_context` becomes richer for free.

---

## Task 1: Modify SummaryContextBuilder and add tests (TDD)

**Files:**
- Modify: `app/services/topics/summary_context_builder.rb` — `agenda_items_data` method (~lines 34-88)
- Modify: `test/services/topics/summary_context_builder_test.rb` — append 3 tests before the closing `end` of the test class

- [ ] **Step 1: Write the failing tests**

Append these three tests to `test/services/topics/summary_context_builder_test.rb` immediately before the final `end` (the one that closes `class SummaryContextBuilderTest`):

```ruby
    test "includes item_details_summary when meeting has a MeetingSummary with matching item_details" do
      @meeting.meeting_summaries.create!(
        summary_type: "minutes_recap",
        generation_data: {
          "item_details" => [
            {
              "agenda_item_title" => "Repair Main St",
              "summary" => "Council approved a $240,000 bid for Main St repaving from Smith Paving Co.",
              "activity_level" => "decision",
              "vote" => "5-0",
              "decision" => "approved",
              "public_hearing" => nil
            }
          ]
        }
      )

      context = @builder.build_context_json
      item = context[:agenda_items].first

      assert_equal "Council approved a $240,000 bid for Main St repaving from Smith Paving Co.",
        item[:item_details_summary]
      assert_equal "decision", item[:item_details_activity_level]
      assert_equal "5-0", item[:item_details_vote]
      assert_equal "approved", item[:item_details_decision]
      assert_nil item[:item_details_public_hearing]
    end

    test "leaves item_details_* fields nil when meeting has no MeetingSummary" do
      # @meeting is set up without a MeetingSummary in the default setup
      context = @builder.build_context_json
      item = context[:agenda_items].first

      assert_nil item[:item_details_summary]
      assert_nil item[:item_details_activity_level]
      assert_nil item[:item_details_vote]
      assert_nil item[:item_details_decision]
      assert_nil item[:item_details_public_hearing]
    end

    test "matches item_details entries by normalized agenda title (numbering + 'as needed')" do
      # Agenda item has no leading number and no suffix; item_details entry has both.
      @meeting.meeting_summaries.create!(
        summary_type: "minutes_recap",
        generation_data: {
          "item_details" => [
            {
              "agenda_item_title" => "7. REPAIR MAIN ST, AS NEEDED",
              "summary" => "Committee discussed Main St potholes; no action.",
              "activity_level" => "discussion",
              "vote" => nil,
              "decision" => nil,
              "public_hearing" => nil
            }
          ]
        }
      )

      context = @builder.build_context_json
      item = context[:agenda_items].first

      assert_equal "Committee discussed Main St potholes; no action.",
        item[:item_details_summary],
        "TitleNormalizer should strip leading '7.' and trailing ', AS NEEDED' to match"
      assert_equal "discussion", item[:item_details_activity_level]
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/services/topics/summary_context_builder_test.rb -n "/item_details/"`

Expected: three FAILs with `undefined method 'item_details_summary'` (actually, it'll print nil because `item[:item_details_summary]` returns nil for a missing key — the assertion `assert_equal ... item[:item_details_summary]` will fail with `Expected "Council approved..." but got nil`).

- [ ] **Step 3: Implement item_details lookup in agenda_items_data**

In `app/services/topics/summary_context_builder.rb`, replace the existing `agenda_items_data` method (currently at lines 34-88) with:

```ruby
    def agenda_items_data
      # Find agenda items for this meeting linked to this topic
      # We need distinct items, but must not break if we iterate over them
      # Fix PG::InvalidColumnReference by using pluck first
      item_ids = @meeting.agenda_items.joins(:agenda_item_topics)
                      .where(agenda_item_topics: { topic_id: @topic.id })
                      .distinct
                      .pluck(:id)

      items = @meeting.agenda_items.where(id: item_ids).order(:order_index)

      # Build a normalized-title → item_details entry lookup from the
      # meeting's latest MeetingSummary. This is the substantive content
      # the minutes analyzer wrote for each item (e.g. "Council approved
      # a $240,000 bid for Main St repaving"). Without this, the per-meeting
      # TopicSummary prompt only sees agenda structure (item.summary, which
      # is usually nil) and writes generic "agenda includes an item titled..."
      # factual_record entries. See issue #94.
      item_details_by_norm_title = build_item_details_index

      items.map do |item|
        # Agenda Item Document Attachments
        doc_attachments = item.meeting_documents.flat_map do |doc|
          # Use extractions if available for granular page citations
          if doc.extractions.any?
            doc.extractions.map do |ex|
              {
                id: doc.id,
                type: doc.document_type,
                citation_id: "doc-#{doc.id}-p#{ex.page_number}",
                label: "#{doc.document_type.humanize} (Page #{ex.page_number})",
                text_preview: ex.cleaned_text&.truncate(1000, separator: " ")
              }
            end
          else
            # Fallback to whole document
            [ {
              id: doc.id,
              type: doc.document_type,
              citation_id: "doc-#{doc.id}",
              label: "#{doc.document_type.humanize}",
              text_preview: doc.extracted_text&.truncate(2000, separator: " ")
            } ]
          end
        end

        # Base Agenda Item Citation
        item_citation = {
          citation_id: "agenda-#{item.id}",
          label: "Agenda Item #{item.number}: #{item.title}",
          text_preview: [ item.summary, item.recommended_action ].compact.join("\n")
        }

        matched_details = item_details_by_norm_title[Topics::TitleNormalizer.normalize(item.title.to_s)]

        {
          id: item.id,
          number: item.number,
          title: item.title,
          summary: item.summary,
          recommended_action: item.recommended_action,
          item_details_summary: matched_details&.dig("summary"),
          item_details_activity_level: matched_details&.dig("activity_level"),
          item_details_vote: matched_details&.dig("vote"),
          item_details_decision: matched_details&.dig("decision"),
          item_details_public_hearing: matched_details&.dig("public_hearing"),
          citation: item_citation,
          attachments: doc_attachments
        }
      end
    end

    def build_item_details_index
      summary = @meeting.meeting_summaries.order(created_at: :desc).first
      return {} unless summary&.generation_data.is_a?(Hash)

      details = summary.generation_data["item_details"]
      return {} unless details.is_a?(Array)

      details.each_with_object({}) do |entry, index|
        next unless entry.is_a?(Hash)
        title = entry["agenda_item_title"]
        next unless title.is_a?(String)
        normalized = Topics::TitleNormalizer.normalize(title)
        index[normalized] = entry
      end
    end
```

Both `agenda_items_data` and the new `build_item_details_index` should be under the existing `private` keyword (which is already in place at line 22-23 of the file).

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `bin/rails test test/services/topics/summary_context_builder_test.rb -n "/item_details/"`

Expected: 3 tests PASS.

- [ ] **Step 5: Run the full summary_context_builder_test.rb file to confirm no regression**

Run: `bin/rails test test/services/topics/summary_context_builder_test.rb`

Expected: 8 tests PASS (5 pre-existing + 3 new).

- [ ] **Step 6: Run the full test suite** — the new fields affect both `generate_topic_summaries` in `SummarizeMeetingJob` (which tests stub or don't exercise) and `recent_raw_context` in `GenerateTopicBriefingJob` (which existing tests access via a mock). The new keys won't break anything but running the full suite confirms.

Run: `bin/rails test`

Expected: all tests pass. If `generate_topic_briefing_job_test.rb` fails because one of its tests inspects `recent_raw_context` entries, that's a hint that the test's assertions need updating — but based on the existing tests (which only check key presence at the top of the context hash, not inside `recent_raw_context`), no failures are expected.

- [ ] **Step 7: Rubocop**

Run: `bin/rubocop app/services/topics/summary_context_builder.rb test/services/topics/summary_context_builder_test.rb`

Expected: clean.

- [ ] **Step 8: Commit**

```bash
git add app/services/topics/summary_context_builder.rb test/services/topics/summary_context_builder_test.rb
git commit -m "$(cat <<'EOF'
feat(topics): plumb item_details into SummaryContextBuilder

Topics::SummaryContextBuilder#agenda_items_data now fetches the
meeting's latest MeetingSummary and, for each linked agenda item,
includes matched item_details content (summary, activity_level,
vote, decision, public_hearing) alongside the existing agenda
structure (title, number, AgendaItem.summary, attachments).

Fixes the starvation that left per-meeting TopicSummary rows
writing "agenda includes an item titled..." boilerplate even when
the minutes analyzer had already captured specific incidents like
"Staff reported fake garbage stickers being found" or "A resident
complained about sticker purchase requirements."

Matching uses Topics::TitleNormalizer (from #93) for tolerant
title comparison across leading numbering, "as needed" / "if
applicable" suffixes, and whitespace variance.

analyze_topic_summary prompt update in the next commit. Refs #94.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Update analyze_topic_summary prompt with data_sources block

**Files:**
- Modify: `lib/prompt_template_data.rb` — the `"analyze_topic_summary"` entry (lines ~451-559)

- [ ] **Step 1: Apply the edit**

Find this block in `lib/prompt_template_data.rb` inside the `"analyze_topic_summary"` entry's `instructions:` HEREDOC:

```
        - Cross-body movement (committee recommends, council approves) is normal
          workflow and not noteworthy. Only flag cross-body patterns when council
          sends a topic back to committee or when a topic bounces repeatedly
          between bodies without resolution.
        </tone_calibration>

        {{committee_context}}
```

Replace it with (the `<data_sources>` block is inserted between `</tone_calibration>` and `{{committee_context}}`):

```
        - Cross-body movement (committee recommends, council approves) is normal
          workflow and not noteworthy. Only flag cross-body patterns when council
          sends a topic back to committee or when a topic bounces repeatedly
          between bodies without resolution.
        </tone_calibration>

        <data_sources>
        Each entry in `agenda_items` now carries two kinds of content. Use them in this priority order when writing `factual_record` entries:

        1. `item_details_summary` (new, PRIMARY) — The SUBSTANTIVE CONTENT of the agenda item from the meeting minutes analyzer. Accompanied by `item_details_activity_level` (`decision | discussion | status_update`), `item_details_vote`, `item_details_decision`, and `item_details_public_hearing`. When this field is present, it tells you what actually happened at this agenda item: specific incidents, committee responses, votes, and resident testimony. Write factual_record entries that name the specific content. Do NOT write "agenda included an item titled X" when `item_details_summary` has real content — that's the starvation pattern this field exists to eliminate.

        2. `summary` and `recommended_action` — The AgendaItem's own scraped fields. Often empty or thin. Fall back here only when `item_details_summary` is nil.

        3. `attachments` — Per-item document excerpts from packets or minutes. Use for packet-specific citations when citing specific pages. Lower priority than `item_details_summary` when both describe the same agenda item.

        When `item_details_summary` is nil for an agenda item (e.g. no minutes yet, or the item was filtered as procedural), it is acceptable to write a short neutral factual_record entry naming what the agenda contained — but keep it to one entry per item and do not fabricate specifics.

        `item_details_activity_level` tells you how much weight to give the entry:
        - `decision`: a vote or formal action happened. Lead with the outcome.
        - `discussion`: substantive discussion, no vote. Lead with the content of the discussion.
        - `status_update`: routine update, usually skippable unless the update names a concrete development.
        </data_sources>

        {{committee_context}}
```

Use the Edit tool. The old_string is unique because `</tone_calibration>\n\n        {{committee_context}}` appears exactly once per template and the leading `- Cross-body movement` line makes the region distinctive.

- [ ] **Step 2: Validate**

Run: `bin/rails prompt_templates:validate`

Expected: all 16 templates present, no errors. No new `{{placeholder}}` tokens were added, so validation should pass cleanly.

- [ ] **Step 3: Populate locally**

Run: `bin/rails prompt_templates:populate`

Expected: output showing `analyze_topic_summary` updated and a new `PromptVersion` row created.

- [ ] **Step 4: Sanity check the DB template has the new block**

Run:
```bash
bin/rails runner 'pt = PromptTemplate.find_by(key: "analyze_topic_summary"); puts pt.instructions.include?("<data_sources>") ? "OK: data_sources block present" : "FAIL: block missing"; puts "length: #{pt.instructions.length}"'
```

Expected: `OK: data_sources block present` with a length noticeably larger than the pre-edit length.

- [ ] **Step 5: Run the full test suite as a sanity check**

Run: `bin/rails test`

Expected: all tests pass. The prompt change does not affect any test (all tests stub `Ai::OpenAiService`).

- [ ] **Step 6: Rubocop**

Run: `bin/rubocop lib/prompt_template_data.rb`

Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add lib/prompt_template_data.rb
git commit -m "$(cat <<'EOF'
feat(prompts): teach analyze_topic_summary about item_details_* fields

Adds a <data_sources> block to the analyze_topic_summary instructions
that names item_details_summary as the PRIMARY source for factual_record
entries and explains the priority order against AgendaItem.summary and
attachments. Describes item_details_activity_level as a weighting signal:
lead with decisions, lead with discussion content, usually skip
status_updates unless they name a concrete development.

This completes issue #94: per-meeting TopicSummary rows can now name
specific incidents from minutes content rather than echoing agenda
structure. Combined with #93's briefing-level plumbing, factual_record
entries should reference real events (fake stickers, resident complaints,
committee dispositions) across both prior_meeting_analyses and
recent_item_details sources.

Refs #94. Parent fix: #93.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Deploy and populate prompt on production

**Files:** (none — deployment only)

- [ ] **Step 1: Run local CI**

Run: `bin/ci`

Expected: setup, rubocop, bundler-audit, importmap audit, brakeman all pass.

- [ ] **Step 2: Run the full test suite**

Run: `bin/rails test`

Expected: all tests pass.

- [ ] **Step 3: Push master**

```bash
git push origin master
```

Expected: two commits pushed (the SummaryContextBuilder fix and the prompt update).

- [ ] **Step 4: Deploy to production**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && bin/kamal deploy
```

Expected: deploy succeeds, kamal-proxy shows the new container healthy, `https://tworiversmatters.com` still loads.

- [ ] **Step 5: Populate prompt templates on prod**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && bin/kamal app exec "bin/rails prompt_templates:populate"
```

Expected: output confirms `analyze_topic_summary` updated in prod DB and a new `PromptVersion` row created.

- [ ] **Step 6: Verify the block landed in prod DB**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && bin/kamal app exec "bin/rails runner 'pt = PromptTemplate.find_by(key: %{analyze_topic_summary}); puts pt.instructions.include?(%{<data_sources>}) ? %{OK} : %{FAIL}; puts %{length: } + pt.instructions.length.to_s'"
```

Expected: `OK` with an increased length.

- [ ] **Step 7: HTTP sanity check**

```bash
curl -sS -o /dev/null -w "HTTP %{http_code} | %{time_total}s\n" https://tworiversmatters.com/
```

Expected: HTTP 200, sub-second.

---

## Task 4: Cascade rerun for topic 513's meetings on production

**Files:** (none — runtime operation)

- [ ] **Step 1: Re-run SummarizeMeetingJob for m94, m8, m178**

These three meetings are topic 513's live appearance set. Re-running each cascades through `generate_topic_summaries` (which now uses the fixed `SummaryContextBuilder`), `PruneHollowAppearancesJob`, and `GenerateTopicBriefingJob`.

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && \
bin/kamal app exec "bin/rails runner '
  [94, 8, 178].each do |mid|
    m = Meeting.find_by(id: mid)
    next unless m
    SummarizeMeetingJob.perform_later(mid)
    puts %{enqueued SummarizeMeetingJob for meeting } + mid.to_s + %{ (} + m.body_name.to_s + %{, } + m.starts_at.to_date.to_s + %{)}
  end
'"
```

Expected: three enqueue lines. Jobs will run in-process via Solid Queue in the Puma worker.

- [ ] **Step 2: Wait for the jobs to drain** (~10 min total)

Each SummarizeMeetingJob takes ~3-4 min. Sequential execution means ~10 min for all three, plus a few extra minutes for the cascaded `GenerateTopicBriefingJob` runs.

Use `ScheduleWakeup` with `delaySeconds: 720` (12 min) rather than polling. Reason for the delay choice: cascade wall time is the bottleneck; 12 min buys enough margin for all three meetings + downstream briefings without needing a second wake.

- [ ] **Step 3: After wake, verify topic 513's ts514 / ts250 / ts674 are no longer generic**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && \
bin/kamal app exec "bin/rails runner '
  t = Topic.find(513)
  puts %{topic_summaries: } + t.topic_summaries.count.to_s
  puts %{topic_appearances: } + t.topic_appearances.count.to_s
  t.topic_summaries.order(:meeting_id).each do |ts|
    m = Meeting.find(ts.meeting_id)
    puts %{--- ts} + ts.id.to_s + %{ meeting=} + ts.meeting_id.to_s + %{ (} + m.starts_at.to_date.to_s + %{) ---}
    fr = (ts.generation_data && ts.generation_data[%{factual_record}]) || []
    fr.each_with_index do |e, i|
      next unless e.is_a?(Hash)
      puts %{[} + i.to_s + %{] } + (e[%{statement}] || e[%{event}] || e.inspect).to_s.truncate(200)
    end
  end
'"
```

Expected (post-fix):
- ts514 (m94) should reference the fake-stickers story ("Staff reported fake garbage stickers being found...", "Manitowoc Disposal notifying DPW and police", "committee declined to revisit the method")
- ts250 (m8) should reference the resident complaint about the sticker purchase requirement
- ts674 (m178) may still be thin because m178 has no minutes yet (packet-only), but should not cross-reference pruned meetings

If any of these are still "agenda includes an item titled...", the fix did not take effect — investigate by reading the updated context builder + prompt on prod.

---

## Task 5: Final verification and issue close-out

**Files:** (none — verification only)

- [ ] **Step 1: Check topic 513's final briefing state**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && \
bin/kamal app exec "bin/rails runner '
  t = Topic.find(513)
  br = t.topic_briefing
  puts %{headline: } + br.headline.to_s.inspect
  puts %{last_full_generation_at: } + br.last_full_generation_at.to_s
  puts %{impact_score: } + t.resident_impact_score.to_s
  fr = (br.generation_data && br.generation_data[%{factual_record}]) || []
  puts %{factual_record count: } + fr.length.to_s
  fr.each_with_index do |e, i|
    next unless e.is_a?(Hash)
    puts %{[} + i.to_s + %{] } + (e[%{date}] || %{?}).to_s + %{ | } + (e[%{meeting}] || %{?}).to_s + %{ | } + (e[%{event}] || e[%{statement}] || e.inspect).to_s.truncate(220)
  end
  ea = br.generation_data && br.generation_data[%{editorial_analysis}]
  if ea
    puts %{--- current_state ---}
    puts (ea[%{current_state}] || %{nil}).to_s
  end
'"
```

Expected:
- `factual_record` references specific incidents (fake stickers / resident complaint / committee disposition) for at least 2 of the entries, not just one
- No entries mention pruned meetings (m132, m146)
- No entries conflate titles across meetings (e.g. "Garbage & Recycling Discussion" should only appear in an m178 entry, not m8)
- `current_state` remains specific + KB-framed

- [ ] **Step 2: Fetch the live topic 513 page**

```bash
curl -sS https://tworiversmatters.com/topics/513 -o /tmp/t513.html && \
grep -c -i "appeared on the agenda\|agenda included .*solid waste" /tmp/t513.html && \
grep -i -E "(fake|sticker|resident)" /tmp/t513.html | head -5
```

Expected:
- Zero matches for "appeared on the agenda" or "agenda included ... solid waste"
- At least one match for "fake" or "sticker" or "resident" (likely multiple)

- [ ] **Step 3: Merge feature branch to master**

(We've been committing directly to master via push in Task 3. Confirm master is clean and aligned.)

```bash
git log origin/master..HEAD --oneline
```

Expected: empty (everything is pushed).

- [ ] **Step 4: Close issues #93 and #94**

```bash
gh issue close 94 --comment "$(cat <<'EOF'
Shipped in commits:
- SummaryContextBuilder item_details plumbing: <sha>
- analyze_topic_summary prompt update: <sha>

Post-deploy cascade:
- Re-ran SummarizeMeetingJob for m94, m8, m178 (topic 513's live meetings)
- Verified ts514 / ts250 / ts674 now reference specific incidents instead of agenda structure

Verification: topic 513's briefing factual_record now has multiple specific entries (fake stickers / resident complaint / etc), no pruned-meeting cross-references, and no cross-meeting title conflation. Closes the context-starvation gap that surfaced during #93 diagnosis.
EOF
)"
```

Replace `<sha>` with the two real SHAs from Task 1 and Task 2.

Then consider whether to also close #93 — it's already shipped, but was left open pending #94's completion. With #94 closed, #93 can be closed too if the topic 513 state looks good end-to-end:

```bash
gh issue close 93 --comment "All three root causes addressed:
- RC1: briefing context plumbing (closed by #93 itself)
- RC1-extended: per-meeting topic summary plumbing (closed by #94)
- RC2: sanitation KB entries (done via admin UI)
- RC3: orphan TopicSummary cleanup (closed by #93 itself)

Topic 513 briefing now shows specific incident content instead of 'appeared on the agenda' boilerplate across both the briefing and its per-meeting topic summaries."
```

(Ask the user whether to close #93 — do not close it autonomously.)

- [ ] **Step 5: Run the full test suite one more time for peace of mind**

```bash
bin/rails test && bin/rubocop
```

Expected: all green.

---

## Out of scope

- No new service class (the inline lookup inside `SummaryContextBuilder` is simple enough that extracting to `Topics::ItemDetailsIndexer` or similar would be speculative abstraction).
- No changes to `Topics::RecentItemDetailsBuilder` from #93 — it serves a different consumer (briefing job's top-level context) and a different shape (flat list across meetings).
- No changes to the `render_topic_summary` prompt — the data_sources change only affects the analysis pass.
- No prod-wide cascade for the 116 other topics affected by the original #93 orphan count. Those will self-heal as their meetings get re-summarized naturally. This plan only covers topic 513 as the canary.
