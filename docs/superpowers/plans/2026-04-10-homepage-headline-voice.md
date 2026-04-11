# Homepage Headline Voice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the meta-commentary homepage headlines ("keeps coming back, vote not reported yet") with specific, stake-forward news by rewriting the `analyze_topic_briefing` prompt, then backfill existing briefings so the change lands on the live homepage.

**Architecture:** Pure prompt edit. The database `PromptTemplate` record for `analyze_topic_briefing` gets a new `instructions` field. `lib/prompt_template_data.rb` is the source-of-truth and gets updated in the same commit. The `prompt_templates:populate` rake task reads the source file and overwrites the database record, which triggers `PromptTemplate#after_save` to auto-create a `PromptVersion` row (the rollback path). Existing `TopicBriefing` records are then backfilled by re-running `Topics::GenerateTopicBriefingJob` for every topic that surfaces on the homepage and topic index. No code changes to models, jobs, services, controllers, or views — the contract between the database template and `Ai::OpenAiService#analyze_topic_briefing` is unchanged.

**Tech Stack:** Rails 8.1, PostgreSQL, `PromptTemplate` ActiveRecord model with auto-versioning (`PromptVersion`), `gpt-5.2` via `ruby-openai`, Solid Queue for background jobs, `tmp/headline_validation.rb` as the validation harness (gitignored, dev-local).

**Spec:** `docs/superpowers/specs/2026-04-10-homepage-headline-voice-design.md` — read Appendix A for the verbatim new `instructions` text.

**Working context:** This plan runs on the `master` branch (no worktree). All changes are reversible via git revert + re-running `bin/rails prompt_templates:populate`. Production rollback is via the admin UI at `/admin/prompt_templates` paired with a re-run of Task 5's backfill.

---

## File Structure

| Path | Action | Purpose |
|---|---|---|
| `lib/prompt_template_data.rb` | Modify (lines 595–~800) | Replace the `instructions` HEREDOC for the `"analyze_topic_briefing"` entry with the new text from spec Appendix A. Keep `system_role` and metadata unchanged. |
| `tmp/headline_validation.rb` | Modify | Update `TOPIC_NAMES` constant to point at structurally different topics for the pre-deploy validation pass. Gitignored. |
| `tmp/verify_headline_success.rb` | Create | One-off verification script that enforces the spec's Success Criteria on `TopicBriefing.headline` and `editorial_analysis.current_state` for all homepage-eligible topics. Gitignored. |
| `tmp/backfill_briefings.rb` | Create | One-off script that calls `Topics::GenerateTopicBriefingJob.perform_now` for topics with `resident_impact_score >= 2` and `last_activity_at` within 30 days. Gitignored. |

No production files are created. The `tmp/` files exist only during implementation and can be discarded after Task 7.

---

### Task 1: Pre-deploy validation against structurally different topics

**Rationale:** The spec's R1 risk is "overfitting to four topics." The validation we ran during brainstorming used the same four topics twice. Before flipping production, re-run the validation script against four **structurally different** topics (thin context, low impact, recently approved, etc.) to catch overfit. This task produces no commit — it's a gate.

**Files:**
- Modify: `tmp/headline_validation.rb` (TOPIC_NAMES constant)

- [ ] **Step 1: Find four structurally different topics with populated briefings**

Run this script to find candidates:

```bash
bin/rails runner '
puts "=== Candidates for pre-deploy validation ==="
puts ""
candidates = [
  "garbage and recycling service changes",
  "fee schedule",
  "wisconsin dnr grant",
  "municipal borrowing",
  "sidewalk program",
  "lincoln ave"
]
candidates.each do |name|
  t = Topic.find_by(name: name)
  if t.nil?
    puts "  MISSING: #{name}"
    next
  end
  tb = t.topic_briefing
  appearances = t.topic_appearances.count
  has_civic = tb&.generation_data&.dig("civic_sentiment").to_a.any?
  has_pc = tb&.generation_data&.dig("editorial_analysis", "process_concerns").present?
  puts "  #{name}"
  puts "    id=#{t.id} impact=#{t.resident_impact_score} appearances=#{appearances} civic_sentiment=#{has_civic ? "YES" : "no"} process_concerns=#{has_pc ? "YES" : "no"}"
end
'
```

Pick **four topics** that together cover:
- (a) one with thin context / low appearance count — tests the "write a quiet honest headline" fallback
- (b) one with `process_concerns` already populated in OLD — tests that the new bar doesn't collapse legitimate concerns
- (c) one with `civic_sentiment` populated — tests bleed into that field if real data exists
- (d) one structurally similar to the brainstorming set as a regression anchor

If none of the candidates satisfy (b) or (c), pick whatever has the most appearances (richest context) as a substitute.

- [ ] **Step 2: Update the TOPIC_NAMES constant in `tmp/headline_validation.rb`**

Edit `tmp/headline_validation.rb` and replace the `TOPIC_NAMES` constant (around line 9) with the four topics chosen in Step 1. Keep the exact same string form as existing entries (lowercase, no punctuation). Example:

```ruby
TOPIC_NAMES = [
  "garbage and recycling service changes",
  "fee schedule",
  "wisconsin dnr grant",
  "municipal borrowing"
].freeze
```

- [ ] **Step 3: Run the validation script**

Run:

```bash
bin/rails runner tmp/headline_validation.rb
```

Expected: the script prints a field-by-field OLD vs NEW diff for each topic. Runtime ~1.5–3 minutes total (4 topics × 2 OpenAI calls × ~15–25s each).

- [ ] **Step 4: Inspect the output against five pass criteria**

For each of the four topics, verify:

1. **Headline passes the banned-closers check.** No NEW headline ends with "no vote has been reported yet", "vote unclear", "still pending", "still no clear decision", "keeps coming back", "keeps circling", "keeps popping up", "contract execution concerns", "discussion expected".
2. **Headline passes the jargon check.** No NEW headline contains untranslated `TID`, `saw-cut`, `revenue bond`, `enterprise fund`, `conditional use permit`, `certified survey map`, `general obligation promissory notes`.
3. **Bleed check clean.** NEW `factual_record` is as dry as OLD or drier. NEW `civic_sentiment` is observational (not editorial). NEW `pattern_observations` is evidence-bound. NEW `process_concerns` is either null or a specific, concrete issue (not "agenda language is high-level").
4. **Fact check.** For at least one NEW output per topic, pick a specific detail (dollar amount, street name, date, business name) and confirm it appears in either the OLD output or the topic's source context. If it doesn't, the model hallucinated — that's a blocker.
5. **No press-release voice.** NEW headlines should not lead with contractor names or technique jargon unless the mechanism IS the story (e.g., 0% financing).

- [ ] **Step 5: If any criterion fails, iterate the prompt in `tmp/headline_validation.rb` and re-run**

Failure modes and fixes:

| Failure | Fix |
|---|---|
| Banned closer slipped through | Add the specific phrase to rule 6's banned list in the `NEW_INSTRUCTIONS` HEREDOC |
| Untranslated jargon | Add the term to the translation list in `<voice>` with an explicit mapping |
| Process concern bleed | Tighten the `<voice_scope>` block's `process_concerns` description with a more specific "DO NOT" statement |
| Factual hallucination | Not a prompt issue — stop and investigate. The pass-1 context may be missing source detail. Escalate to user. |
| Press-release voice | Strengthen rule 4a with the specific failure example as a BAD case in the `<headline_criteria>` block |

After each iteration, re-run Step 3. Repeat until all four topics pass all five criteria.

- [ ] **Step 6: Record the validation result**

Once all four topics pass, note in a scratch file or comment the four topic names validated, the iteration count, and the final OpenAI cost (~$2 budget assumed). No commit at this step — the iterations live in the gitignored `tmp/` script. Proceed to Task 2.

---

### Task 2: Update `lib/prompt_template_data.rb`

**Files:**
- Modify: `lib/prompt_template_data.rb:595-~800` (the `"analyze_topic_briefing"` entry's `instructions:` HEREDOC)

- [ ] **Step 1: Read the current state of the analyze_topic_briefing entry**

Run:

```bash
bin/rails runner 'puts PromptTemplateData::PROMPTS["analyze_topic_briefing"][:instructions].lines.first(3).join'
```

Also read lines 595–800 of `lib/prompt_template_data.rb` directly to confirm the HEREDOC delimiter (likely `PROMPT`) and the structure.

Expected: prints the first three lines of the current `instructions` block (`Analyze this topic's history across meetings...`).

- [ ] **Step 2: Replace the instructions HEREDOC with the new text from spec Appendix A**

Use the Edit tool to replace the HEREDOC body. The new text is in `docs/superpowers/specs/2026-04-10-homepage-headline-voice-design.md` under "Appendix A: New `instructions` text". The replacement must:

- Preserve the `{{committee_context}}` placeholder verbatim
- Preserve the `{{context}}` placeholder verbatim
- Preserve the surrounding Ruby HEREDOC syntax (`<<~PROMPT.strip ... PROMPT`)
- Leave the `system_role:` value untouched
- Leave all metadata (key, name, description, usage_context, model_tier, placeholders) untouched

Replace only the body between `instructions: <<~PROMPT.strip` and the closing `PROMPT` delimiter for the `"analyze_topic_briefing"` entry. Do not touch any other entry in the file.

- [ ] **Step 3: Verify the file loads and parses as Ruby**

Run:

```bash
bin/rails runner 'puts PromptTemplateData::PROMPTS["analyze_topic_briefing"][:instructions].length'
```

Expected: prints a single integer, roughly `12000` to `13000` (the new instructions are ~12,600 chars — current is 5,057).

If the file has a syntax error, the runner will print a `SyntaxError` traceback. Fix the HEREDOC delimiter or escape any stray backticks and re-run.

- [ ] **Step 4: Verify both placeholders are present in the new instructions**

Run:

```bash
bin/rails runner '
text = PromptTemplateData::PROMPTS["analyze_topic_briefing"][:instructions]
puts "has {{committee_context}}: #{text.include?("{{committee_context}}")}"
puts "has {{context}}: #{text.include?("{{context}}")}"
puts "has <headline_criteria>: #{text.include?("<headline_criteria>")}"
puts "has <voice_scope>: #{text.include?("<voice_scope>")}"
'
```

Expected output:
```
has {{committee_context}}: true
has {{context}}: true
has <headline_criteria>: true
has <voice_scope>: true
```

If any of those print `false`, the replacement dropped content. Stop and inspect.

- [ ] **Step 5: Confirm the system_role is unchanged**

Run:

```bash
bin/rails runner 'puts PromptTemplateData::PROMPTS["analyze_topic_briefing"][:system_role]'
```

Expected: prints the existing five-line neighborhood reporter system role (starting "You are a neighborhood reporter writing for residents of Two Rivers, WI."). If this value changed, revert it — the spec says `system_role` is not touched.

- [ ] **Step 6: Commit**

```bash
git add lib/prompt_template_data.rb
git commit -m "$(cat <<'EOF'
feat(prompts): rewrite analyze_topic_briefing for homepage headline voice

Replace status-update headlines ("keeps coming back, vote not reported
yet") with specific, stake-forward news. Adds headline_criteria block
(10 rules), voice_scope bleed fence, expanded jargon translations, and
NEUTRAL. annotations on all non-voice fields in the extraction schema.

Validated against 8 topics across two iterations. Zero bleed detected
in factual_record, civic_sentiment, pattern_observations, or
process_concerns.

Spec: docs/superpowers/specs/2026-04-10-homepage-headline-voice-design.md

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Populate the database record and verify auto-versioning

**Files:**
- No file modifications. This task runs a rake task and verifies the database state.

- [ ] **Step 1: Capture the current database state before the populate**

Run:

```bash
bin/rails runner '
t = PromptTemplate.find_by!(key: "analyze_topic_briefing")
puts "current instructions chars: #{t.instructions.length}"
puts "current version count: #{t.versions.count}"
puts "latest version id: #{t.versions.order(:created_at).last&.id}"
'
```

Note the `instructions chars` (should be around 5,057 — the old value) and the `version count`. Record these values — they are the baseline for confirming the update worked.

- [ ] **Step 2: Run the populate rake task**

Run:

```bash
bin/rails prompt_templates:populate
```

Expected output includes `Updated 'analyze_topic_briefing'` among the list of updated templates. Exit code 0.

- [ ] **Step 3: Verify the database now matches the new source text**

Run:

```bash
bin/rails runner '
t = PromptTemplate.find_by!(key: "analyze_topic_briefing")
file_text = PromptTemplateData::PROMPTS["analyze_topic_briefing"][:instructions].strip
puts "db instructions chars: #{t.instructions.length}"
puts "file instructions chars: #{file_text.length}"
puts "match: #{t.instructions == file_text}"
puts "has <headline_criteria>: #{t.instructions.include?("<headline_criteria>")}"
puts "has <voice_scope>: #{t.instructions.include?("<voice_scope>")}"
puts "has {{committee_context}}: #{t.instructions.include?("{{committee_context}}")}"
puts "has {{context}}: #{t.instructions.include?("{{context}}")}"
'
```

Expected output:
```
db instructions chars: ~12600
file instructions chars: ~12600
match: true
has <headline_criteria>: true
has <voice_scope>: true
has {{committee_context}}: true
has {{context}}: true
```

If `match: false`, the populate didn't run or the file has a trailing newline mismatch. Rerun Step 2 and compare.

- [ ] **Step 4: Verify auto-versioning created a new `PromptVersion` row**

Run:

```bash
bin/rails runner '
t = PromptTemplate.find_by!(key: "analyze_topic_briefing")
puts "new version count: #{t.versions.count}"
latest = t.versions.order(:created_at).last
puts "latest version id: #{latest.id}"
puts "latest editor_note: #{latest.editor_note}"
puts "latest instructions chars: #{latest.instructions.length}"
'
```

Expected: `new version count` is one greater than the baseline recorded in Step 1. `editor_note` is `"Populated from OpenAiService heredoc"`. `instructions chars` matches the new database text (~12,600).

If the version count did not increment, the `after_save` callback didn't fire — which means the `update!` call either failed silently or the text was identical. Re-read `lib/prompt_template_data.rb` against the database, find the discrepancy, and fix.

- [ ] **Step 5: Smoke-test that `Ai::OpenAiService#analyze_topic_briefing` still runs end-to-end**

Run a single briefing against one topic to confirm the new prompt interpolates correctly and produces valid JSON. Pick a low-impact topic so the test cost is low:

```bash
bin/rails runner '
topic = Topic.approved.where("resident_impact_score >= ?", 2).first
meeting = topic.topic_appearances.joins(:meeting).order("meetings.starts_at DESC").first.meeting
puts "Smoke-testing on topic: #{topic.name}"
context = Topics::GenerateTopicBriefingJob.new.send(:build_briefing_context, topic, meeting, RetrievalService.new)
result_str = Ai::OpenAiService.new.analyze_topic_briefing(context)
result = JSON.parse(result_str)
puts "headline: #{result["headline"]}"
puts "upcoming_headline: #{result["upcoming_headline"].inspect}"
puts "current_state: #{result.dig("editorial_analysis", "current_state")}"
puts "has factual_record: #{result["factual_record"].is_a?(Array)}"
puts "has resident_impact: #{result["resident_impact"].is_a?(Hash)}"
'
```

Expected: prints a headline that passes the banned-closers and jargon checks, prints a current_state sentence or two, confirms `factual_record` is an array and `resident_impact` is a hash.

If this call fails with a `JSON::ParserError`, the prompt produced invalid JSON — likely a stray unescaped quote in the new text. Inspect, fix `lib/prompt_template_data.rb`, re-run `prompt_templates:populate`, and retry.

If this call fails with a `KeyError` from the `PromptTemplate#interpolate` method, a placeholder was dropped — re-check Task 2 Step 4.

No commit at this step. This is a verification gate.

---

### Task 4: Create the backfill script

**Files:**
- Create: `tmp/backfill_briefings.rb`

- [ ] **Step 1: Write the backfill script**

Create `tmp/backfill_briefings.rb` with this exact content:

```ruby
# tmp/backfill_briefings.rb
#
# Re-runs Topics::GenerateTopicBriefingJob synchronously for every topic
# that currently surfaces on the homepage or topic index, so that existing
# TopicBriefing records pick up the new analyze_topic_briefing prompt.
#
# Scope: approved topics with resident_impact_score >= 2 and
# last_activity_at within the last 30 days. This matches HomeController's
# WIRE_MIN_IMPACT and ACTIVITY_WINDOW thresholds.
#
# Usage: bin/rails runner tmp/backfill_briefings.rb

topics = Topic.approved
  .where("resident_impact_score >= ?", 2)
  .where("last_activity_at > ?", 30.days.ago)
  .order(resident_impact_score: :desc, last_activity_at: :desc)
  .to_a

puts "Backfilling #{topics.size} topics..."
puts ""

succeeded = 0
failed = []

topics.each_with_index do |topic, i|
  meeting = topic.topic_appearances
    .joins(:meeting)
    .order("meetings.starts_at DESC")
    .first&.meeting

  if meeting.nil?
    puts "[#{i + 1}/#{topics.size}] SKIP: #{topic.name} (no meeting)"
    next
  end

  print "[#{i + 1}/#{topics.size}] #{topic.name} (impact=#{topic.resident_impact_score})... "
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  begin
    Topics::GenerateTopicBriefingJob.perform_now(
      topic_id: topic.id,
      meeting_id: meeting.id
    )
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    puts "OK (#{duration.round(1)}s)"
    succeeded += 1
  rescue => e
    puts "FAILED: #{e.class}: #{e.message}"
    failed << { topic: topic.name, error: "#{e.class}: #{e.message}" }
  end
end

puts ""
puts "Done. #{succeeded}/#{topics.size} succeeded."
if failed.any?
  puts ""
  puts "Failures:"
  failed.each { |f| puts "  - #{f[:topic]}: #{f[:error]}" }
end
```

- [ ] **Step 2: Dry-run the topic query to confirm scope**

Before burning API calls, confirm how many topics the script will hit. Run:

```bash
bin/rails runner '
count = Topic.approved
  .where("resident_impact_score >= ?", 2)
  .where("last_activity_at > ?", 30.days.ago)
  .count
puts "Topics in scope for backfill: #{count}"
puts "Estimated cost: $#{(count * 0.10).round(2)} (at ~$0.10 per topic for analyze + render)"
puts "Estimated runtime: ~#{(count * 0.5).round} min (at ~30s per topic)"
'
```

Expected: prints a count between 15 and 50. If the count is unexpectedly large (>100), stop and review the scope predicate — the new prompt may not be worth running at that volume.

---

### Task 5: Run the backfill and monitor

**Files:**
- No file modifications. This task runs the backfill script created in Task 4.

- [ ] **Step 1: Run the backfill script in the foreground**

Run:

```bash
bin/rails runner tmp/backfill_briefings.rb
```

Expected: the script prints one line per topic, either `OK (Xs)` or `FAILED: ...`. Total runtime is roughly 30 seconds per topic × N topics. For ~30 topics, expect 15 minutes. The script runs `perform_now` so each job runs synchronously in the foreground — no need to monitor Solid Queue separately.

- [ ] **Step 2: Verify every topic in scope got a fresh briefing**

After the script completes, verify that every in-scope topic's `TopicBriefing.updated_at` is within the last hour:

```bash
bin/rails runner '
topics = Topic.approved
  .where("resident_impact_score >= ?", 2)
  .where("last_activity_at > ?", 30.days.ago)
  .to_a

stale = topics.reject do |t|
  t.topic_briefing && t.topic_briefing.updated_at > 1.hour.ago
end

puts "In scope: #{topics.size}"
puts "Freshly backfilled: #{topics.size - stale.size}"
puts ""
if stale.any?
  puts "Stale topics (did not backfill):"
  stale.each { |t| puts "  - #{t.name} (briefing updated: #{t.topic_briefing&.updated_at&.to_s || "no briefing"})" }
end
'
```

Expected: every topic in scope was freshly backfilled. If any are stale, re-run the backfill for those specific topics:

```bash
bin/rails runner '
["topic name 1", "topic name 2"].each do |name|
  t = Topic.find_by(name: name)
  m = t.topic_appearances.joins(:meeting).order("meetings.starts_at DESC").first.meeting
  Topics::GenerateTopicBriefingJob.perform_now(topic_id: t.id, meeting_id: m.id)
end
'
```

- [ ] **Step 3: Spot-check one backfilled briefing end-to-end**

Pick one topic from the backfill and print its full generation_data:

```bash
bin/rails runner '
topic = Topic.approved.where("resident_impact_score >= ?", 4).order(last_activity_at: :desc).first
b = topic.topic_briefing
puts "Topic: #{topic.name}"
puts ""
puts "headline: #{b.headline}"
puts "upcoming_headline: #{b.upcoming_headline.inspect}"
puts ""
puts "current_state: #{b.generation_data.dig("editorial_analysis", "current_state")}"
puts ""
puts "process_concerns: #{b.generation_data.dig("editorial_analysis", "process_concerns").inspect}"
puts "pattern_observations: #{(b.generation_data.dig("editorial_analysis", "pattern_observations") || []).size} entries"
puts "factual_record: #{(b.generation_data["factual_record"] || []).size} entries"
puts "civic_sentiment: #{(b.generation_data["civic_sentiment"] || []).size} entries"
'
```

Expected: `headline` uses the new voice (specific detail, no banned closer). `current_state` reads as the opening paragraph of "The Story". `process_concerns` is either null or concrete. `factual_record` is dry.

---

### Task 6: Create the success-criteria verifier and run it

**Files:**
- Create: `tmp/verify_headline_success.rb`

The spec's Success Criteria section lists six testable assertions. This task automates the first four and guides manual checks on the last two.

- [ ] **Step 1: Write the verification script**

Create `tmp/verify_headline_success.rb` with this exact content:

```ruby
# tmp/verify_headline_success.rb
#
# Verifies the spec's Success Criteria for the homepage headline voice
# change. Runs four automated checks on all homepage-eligible briefings
# and prints an inline sample for the two manual checks.
#
# Usage: bin/rails runner tmp/verify_headline_success.rb

BANNED_CLOSERS = [
  "no vote has been reported yet",
  "vote unclear",
  "still pending",
  "still no clear decision",
  "keeps coming back",
  "keeps circling",
  "keeps popping up",
  "contract execution concerns",
  "discussion expected",
  "still not clear",
  "hasn't been spelled out"
].freeze

UNTRANSLATED_JARGON = [
  /\bTID\b/,
  /\bT\.I\.D\.\b/i,
  /\bsaw-cut/i,
  /\brevenue bond/i,
  /\benterprise fund/i,
  /\bconditional use permit/i,
  /\bcertified survey map/i,
  /\bgeneral obligation promissory note/i
].freeze

# A headline "leads with a concrete detail" if its first 40 characters
# contain a dollar amount, a year, a street name, a percentage, a
# specific program name, or a month abbreviation.
CONCRETE_LEAD_PATTERNS = [
  /\$[\d,.]+/,
  /\b20\d\d\b/,
  /\b\d+(?:st|nd|rd|th)\b/i,
  /\b\d+%/,
  /\b(?:Lincoln|Washington|Main|Memorial|Forest|Twin)/i,
  /\bCouncil\s+(?:votes|picks)/i,
  /\b(?:Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|Jan|Feb|Mar)\b/
].freeze

topics = Topic.approved
  .where("resident_impact_score >= ?", 2)
  .where("last_activity_at > ?", 30.days.ago)
  .includes(:topic_briefing)
  .to_a

puts "Verifying #{topics.size} homepage-eligible topics..."
puts ""

violations = {
  banned_closer: [],
  jargon: [],
  no_concrete_lead: [],
  missing_briefing: [],
  missing_headline: []
}

topics.each do |topic|
  briefing = topic.topic_briefing
  if briefing.nil?
    violations[:missing_briefing] << topic.name
    next
  end
  headline = briefing.headline.to_s
  if headline.empty?
    violations[:missing_headline] << topic.name
    next
  end

  BANNED_CLOSERS.each do |phrase|
    if headline.downcase.include?(phrase)
      violations[:banned_closer] << { topic: topic.name, headline: headline, phrase: phrase }
    end
  end

  UNTRANSLATED_JARGON.each do |pattern|
    if headline.match?(pattern)
      violations[:jargon] << { topic: topic.name, headline: headline, match: headline.match(pattern)[0] }
    end
  end

  lead = headline[0, 40]
  unless CONCRETE_LEAD_PATTERNS.any? { |p| lead.match?(p) }
    violations[:no_concrete_lead] << { topic: topic.name, headline: headline }
  end
end

# Criterion 1: no banned closers
puts "=== Criterion 1: No banned closers ==="
if violations[:banned_closer].empty?
  puts "  PASS - 0/#{topics.size} headlines contain banned closers"
else
  puts "  FAIL - #{violations[:banned_closer].size} headlines contain banned closers:"
  violations[:banned_closer].each do |v|
    puts "    #{v[:topic]}: \"#{v[:headline]}\" (banned: #{v[:phrase]})"
  end
end
puts ""

# Criterion 2 & 3: no quoted jargon / untranslated terms
puts "=== Criterion 2 & 3: No untranslated jargon ==="
if violations[:jargon].empty?
  puts "  PASS - 0/#{topics.size} headlines contain untranslated jargon"
else
  puts "  FAIL - #{violations[:jargon].size} headlines contain untranslated jargon:"
  violations[:jargon].each do |v|
    puts "    #{v[:topic]}: \"#{v[:headline]}\" (match: #{v[:match]})"
  end
end
puts ""

# Criterion 4: at least 2/3 lead with a concrete detail
puts "=== Criterion 4: At least 2/3 of headlines lead with a concrete detail ==="
concrete_count = topics.size - violations[:no_concrete_lead].size - violations[:missing_briefing].size - violations[:missing_headline].size
threshold = (topics.size * 2.0 / 3).ceil
puts "  Concrete leads: #{concrete_count}/#{topics.size}"
puts "  Threshold: #{threshold}"
if concrete_count >= threshold
  puts "  PASS"
else
  puts "  FAIL - below #{threshold} threshold. Headlines without concrete leads:"
  violations[:no_concrete_lead].first(10).each { |v| puts "    #{v[:topic]}: \"#{v[:headline]}\"" }
end
puts ""

# Criterion 5: sample 5 random briefings for manual bleed review
puts "=== Criterion 5: MANUAL REVIEW - 5 random briefings for bleed check ==="
puts "  Read each sample below and confirm factual_record, civic_sentiment,"
puts "  pattern_observations, and process_concerns read as dry / observational."
puts "  Any editorial voice, manufactured drama, or loaded language in these"
puts "  fields is a bleed failure."
puts ""

sample = topics.reject { |t| t.topic_briefing.nil? }.sample(5)
sample.each_with_index do |topic, i|
  gd = topic.topic_briefing.generation_data || {}
  puts "  [#{i + 1}] #{topic.name}"
  puts "      headline: #{topic.topic_briefing.headline}"
  puts ""
  fr = (gd["factual_record"] || []).first(2)
  puts "      factual_record (first 2):"
  fr.each { |e| puts "        - [#{e['date']}] #{e['event'].to_s[0, 200]}" }
  cs = (gd["civic_sentiment"] || []).first(2)
  puts "      civic_sentiment (first 2): #{cs.any? ? '' : '(empty)'}"
  cs.each { |e| puts "        - #{e['observation'].to_s[0, 200]}" }
  po = gd.dig("editorial_analysis", "pattern_observations") || []
  puts "      pattern_observations (#{po.size}):"
  po.first(2).each { |p| puts "        - #{p.to_s[0, 200]}" }
  pc = gd.dig("editorial_analysis", "process_concerns")
  puts "      process_concerns: #{pc.nil? ? '(null)' : pc.to_s[0, 300]}"
  puts ""
end

# Criterion 6: fact-grounding spot check
puts "=== Criterion 6: MANUAL REVIEW - fact-grounding spot check ==="
puts "  For the highest-impact topic with a dollar amount in the headline,"
puts "  verify the dollar amount appears in the topic's prior summaries or"
puts "  recent meeting context. If the amount is nowhere in the source chain,"
puts "  the model hallucinated and the prompt change must be reverted."
puts ""

dollar_topic = topics
  .reject { |t| t.topic_briefing.nil? }
  .select { |t| t.topic_briefing.headline.to_s.match?(/\$[\d,.]+/) }
  .max_by(&:resident_impact_score)

if dollar_topic
  puts "  Topic: #{dollar_topic.name} (impact=#{dollar_topic.resident_impact_score})"
  puts "  Headline: #{dollar_topic.topic_briefing.headline}"
  amount_match = dollar_topic.topic_briefing.headline.match(/\$[\d,.]+(?:\s*(?:million|billion))?/i)
  amount = amount_match ? amount_match[0] : nil
  puts "  Amount to verify: #{amount.inspect}"
  puts ""
  puts "  Prior topic summaries (oldest to newest):"
  dollar_topic.topic_summaries.joins(:meeting).order("meetings.starts_at ASC").each do |ts|
    gd_str = ts.generation_data.to_json
    contains = amount && gd_str.include?(amount.gsub(/[\s,]/, "").gsub(/million|billion/i, ""))
    marker = contains ? "FOUND" : "     "
    puts "    #{marker} #{ts.meeting.body_name} #{ts.meeting.starts_at.to_date}"
  end
  puts ""
  puts "  If FOUND appears above, the amount is grounded. If not, manually"
  puts "  inspect the most recent meeting document for the amount."
else
  puts "  No homepage-eligible topic has a dollar amount in its headline."
  puts "  Pick a different specific detail (street name, date) to spot-check manually."
end

puts ""
puts "=" * 60
auto_failed = violations[:banned_closer].any? ||
              violations[:jargon].any? ||
              (concrete_count < threshold) ||
              violations[:missing_briefing].any? ||
              violations[:missing_headline].any?

if auto_failed
  puts "AUTOMATED CHECKS: FAIL"
  puts "Fix the violations above before proceeding."
  exit 1
else
  puts "AUTOMATED CHECKS: PASS"
  puts "Now read the samples printed under Criteria 5 and 6 and confirm"
  puts "them manually before deploying."
end
```

- [ ] **Step 2: Run the verification script**

Run:

```bash
bin/rails runner tmp/verify_headline_success.rb
```

Expected: prints four automated check results and two manual-check instructions. The automated section ends with `AUTOMATED CHECKS: PASS`.

If any automated check fails, the script prints the offending headlines. Possible fixes:

| Failure | Action |
|---|---|
| Banned closer | A specific topic's briefing did not regenerate with the new prompt. Re-run `Topics::GenerateTopicBriefingJob.perform_now(topic_id: X, meeting_id: Y)` for that topic. |
| Untranslated jargon | Same — re-run the briefing for that topic. If re-running produces the same jargon, the prompt needs another iteration; escalate to user. |
| Concrete-lead threshold | Some topics with thin context produced quiet headlines that don't match the regex patterns. Inspect the failing headlines manually. If they're legitimately dry but accurate (which is allowed by the prompt), lower the threshold or accept the near-miss. |
| Missing briefing | A topic didn't get backfilled in Task 5. Re-run the backfill for that topic. |

- [ ] **Step 3: Read the Criterion 5 sample output inline**

The verification script already printed five random briefings under "Criterion 5: MANUAL REVIEW". Read each of the five samples and confirm that for every sample:
- `factual_record` entries read as dry, chronological reporting — no framing, no editorial voice
- `civic_sentiment` entries are observational ("residents pushed back", "drew complaints") — not interpretive or dramatic
- `pattern_observations` are evidence-bound (specific counts, specific bodies, specific dates)
- `process_concerns` is either null or a concrete, specific issue — not a vague "agenda language is high-level" observation

If any sample shows bleed (editorial voice, manufactured drama, loaded language), record which topic and which field, stop, and escalate to user. The fix is another prompt iteration with a stronger bleed fence on the specific field that leaked.

- [ ] **Step 4: Read the Criterion 6 fact-grounding spot check output inline**

The verification script already picked the highest-impact topic with a dollar amount in the headline and printed a FOUND / blank marker next to each prior topic summary showing whether the amount appears in that summary's `generation_data`. Read the output and confirm at least one FOUND marker appears.

If no FOUND marker appears, the dollar amount may still be in a meeting document that the topic summary didn't carry forward. Do a deeper spot-check manually:

```bash
bin/rails runner '
topic = Topic.find_by(name: "TOPIC_NAME_FROM_SCRIPT_OUTPUT")
amount = "2437152"  # strip commas and dollar sign
topic.topic_appearances.joins(:meeting).order("meetings.starts_at DESC").limit(3).each do |app|
  app.meeting.meeting_documents.where.not(extracted_text: [nil, ""]).each do |d|
    if d.extracted_text.include?(amount)
      puts "FOUND in #{d.document_type} on #{app.meeting.body_name} #{app.meeting.starts_at.to_date}"
    end
  end
end
'
```

Replace `TOPIC_NAME_FROM_SCRIPT_OUTPUT` and `2437152` with the values printed by the verification script (the topic name and the bare numeric form of the amount).

If the amount still cannot be found in any source document, the model hallucinated. This is a blocker for production — escalate to user and plan to revert the prompt change via the rollback procedure.

- [ ] **Step 5: Visually confirm the homepage**

Start the dev server:

```bash
bin/dev
```

Open `http://localhost:3000/` in a browser. Confirm:
- The twelve topic cards render without errors
- Each card's headline reads in the new voice (specific detail, no "keeps coming back" filler)
- The "What to Watch" and "The Story" sections on at least one topic detail page (`/topics/<slug>`) also read in the new voice
- Nothing looks broken or unstyled

No commit at this step. Visual confirmation is a gate.

---

### Task 7: Optional cleanup

**Files:**
- Optional: delete `tmp/headline_validation.rb`, `tmp/backfill_briefings.rb`, `tmp/verify_headline_success.rb`

- [ ] **Step 1: Decide whether to keep or delete the tmp/ scripts**

The three `tmp/` scripts are all gitignored and dev-local. Options:

**Keep them:** useful as reference for future prompt iterations. They cost nothing to keep since they're not in version control.

**Delete them:** keeps the working directory tidy.

**Recommendation:** keep `tmp/headline_validation.rb` (it's the prompt iteration harness, valuable for future changes). Delete `tmp/backfill_briefings.rb` and `tmp/verify_headline_success.rb` after one successful run — they were scoped to this single change.

- [ ] **Step 2: If keeping, document them in an inline comment or a dev note**

Optionally, add a comment at the top of `tmp/headline_validation.rb` noting its origin spec for future reference. No commit (tmp/ is gitignored).

- [ ] **Step 3: Check the final state of the branch**

Run:

```bash
git status
git log --oneline -5
```

Expected: a single commit on master for the `lib/prompt_template_data.rb` change. Working tree clean except for `.claude/` and any `tmp/` files that were kept.

---

## Verification Summary

By the end of this plan:

| Spec Success Criterion | Verified in |
|---|---|
| 1. No banned closers on homepage headlines | Task 6 Step 2 (automated) |
| 2. No quoted jargon in homepage headlines | Task 6 Step 2 (automated) |
| 3. No untranslated terms from the translation list | Task 6 Step 2 (automated) |
| 4. At least 8/12 homepage headlines lead with a concrete detail | Task 6 Step 2 (automated; threshold is 2/3 of backfilled topics) |
| 5. 5 random briefings show neutral factual_record / civic_sentiment / pattern_observations / process_concerns | Task 6 Step 3 (manual) |
| 6. No fabricated dates, amounts, or business names | Task 6 Step 4 (manual spot-check) |

## Rollback Procedure

If a regression is discovered after Task 5 (backfill) completes:

1. Run `bin/rails runner 'PromptTemplate.find_by(key: "analyze_topic_briefing").versions.order(:created_at).pluck(:id, :created_at, :editor_note)'` to find the previous version's ID.
2. In the admin UI at `/admin/prompt_templates`, select "Topic Briefing Analysis", find the prior `PromptVersion`, and copy its `instructions` text back into the current record. Save. A new `PromptVersion` row is created automatically as the rollback record.
3. Alternatively, revert `lib/prompt_template_data.rb` with `git revert <commit>` and run `bin/rails prompt_templates:populate` to push the old text back.
4. Re-run Task 4 + Task 5 (the backfill script) to regenerate the briefings with the restored prompt.
