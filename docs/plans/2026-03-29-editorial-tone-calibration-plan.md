# Editorial Tone Calibration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Calibrate AI analysis prompts so editorial intensity matches stakes — factual language for routine business, skeptical edge for high-impact items — without loaded characterizations or manufactured FUD.

**Architecture:** Prompt text changes across three analysis templates, editorial voice updates in two governance docs, a community context seed reframe, and a minor schema change (`process_concerns` from array to nullable string) with backward-compatible rendering.

**Tech Stack:** Ruby on Rails, prompt templates in `lib/prompt_template_data.rb`, Minitest

**Design spec:** `docs/plans/2026-03-29-editorial-tone-calibration-design.md`

---

### Task 1: Update `analyze_topic_briefing` prompt — voice, constraints, schema

**Files:**
- Modify: `lib/prompt_template_data.rb:546-607`

- [ ] **Step 1: Replace the voice section**

In `lib/prompt_template_data.rb`, find the `<voice>` block inside `analyze_topic_briefing` (lines 548-559) and replace it:

```ruby
        <voice>
        - Write like a sharp neighbor who reads the agendas, not a policy analyst.
        - Be skeptical of process and decisions, not of people.
        - Translate jargon: "general obligation promissory notes" -> "borrowing",
          "land disposition" -> "selling city land", "parameters" -> "limits".
        - NEVER reference your own source limitations. Don't say "the record
          provided does not show" or "in the materials provided." If you don't
          know the outcome, say "No vote has been reported yet" or "Still pending."
        - Keep it short. These readers scan, they don't study.
        - Note who is affected by decisions and how. You can infer this from
          context, knowledgebase, public comment, and patterns over time — it
          won't be stated explicitly in city documents.
        - Do not ascribe malice or bad intent to individuals.
        </voice>
```

The change: line 557 "Note who benefits from decisions when relevant." becomes the new "Note who is affected" language.

- [ ] **Step 2: Add tone_calibration and update constraints**

Replace the `<constraints>` block (lines 561-569) with:

```ruby
        <tone_calibration>
        - Match editorial intensity to the stakes. High-impact decisions (major
          rezonings, large contracts, tax changes) deserve more scrutiny than
          routine approvals.
        - Use direct, accurate language — not loaded characterizations:
          - "claims" (when the city projects future benefits), not "pitched as"
            or "sold as"
          - "no one spoke at the public hearing" not "quietly" or "with limited
            scrutiny" — then note whether low engagement is surprising given
            the stakes
          - "passed unanimously" not "green-lit" or "rubber-stamped"
          - State implications directly: "the rezoning expands allowed uses to
            include retail and housing" — not "opens the door" or speculative
            scenarios about what might happen later
        - Low public engagement on high-stakes items is worth noting as an
          observation — but remember that in a small city, residents may not
          engage because of social capital costs, belief that input won't matter,
          or simply not tracking the issue. Don't assume silence means satisfaction
          and don't assume it means the decision was sneaked through.
        - Cross-body movement (committee recommends, council approves) is normal
          workflow and not noteworthy. Only flag cross-body patterns when council
          sends a topic back to committee or when a topic bounces repeatedly
          between bodies without resolution.
        </tone_calibration>

        <constraints>
        - Factual claims must be grounded in the source data. No evidence = don't state it.
        - Civic sentiment: observational ("residents pushed back", "drew complaints").
        - Note deferrals, recurrence, disappearance — these are patterns residents care about.
        - Don't invent continuity that isn't in the data.
        - Most government business is routine. A null process_concerns and an
          empty pattern_observations array reflect good analysis, not a gap.
        - For citations, use the meeting/committee name and date — NOT internal IDs.
          Good: "City Council, Nov 17" or "Public Works Committee, Jan 27"
          Bad: "[agenda-309]" or "[appearance-2481]"
        </constraints>
```

- [ ] **Step 3: Update the JSON schema field descriptions**

In the `<extraction_spec>` block (lines 576-606), replace the `editorial_analysis` object:

```ruby
          "editorial_analysis": {
            "current_state": "1-2 sentences. Plain language. What just happened or where it stands.",
            "pattern_observations": ["Observations about patterns when supported by the timeline — repeated deferrals, topic disappearing without resolution, repeated bouncing between bodies. Empty array is normal and expected for most topics."],
            "process_concerns": "A specific, concrete process issue if one exists (e.g., topic deferred 3+ times, public hearing requirement skipped, repeated send-backs between bodies without resolution). Null for most topics — routine government process is not a concern, and a null field is expected.",
            "what_to_watch": "One sentence about what's next, or null"
          },
```

- [ ] **Step 4: Verify the prompt template loads**

Run: `bin/rails runner "puts PromptTemplateData::TEMPLATES['analyze_topic_briefing'][:instructions][0..200]"`

Expected: prints the first 200 chars of the updated instructions without error.

- [ ] **Step 5: Commit**

```bash
git add lib/prompt_template_data.rb
git commit -m "feat: calibrate analyze_topic_briefing tone — voice, constraints, schema"
```

---

### Task 2: Update `analyze_topic_summary` prompt — framing instruction and tone calibration

**Files:**
- Modify: `lib/prompt_template_data.rb:421-432`

- [ ] **Step 1: Update the governance_constraints block**

In `lib/prompt_template_data.rb`, find the `<governance_constraints>` block inside `analyze_topic_summary` (lines 426-432) and replace line 429:

```ruby
        <governance_constraints>
        - Topic Governance is binding.
        - Factual Record: Must have citations. If no document evidence, do not state as fact.
        - Institutional Framing: Staff summaries and agenda titles reflect the
          city's perspective — note them as such. They may be accurate, incomplete,
          or self-serving depending on context. Don't default to treating them as
          spin, but don't accept them uncritically either.
        - Civic Sentiment: Use observational language ("appears to", "residents expressed"). No unanimity claims.
        - Continuity: Explicitly note recurrence, deferrals, and cross-body progression.
        </governance_constraints>
```

- [ ] **Step 2: Add tone_calibration block**

Add the `<tone_calibration>` block (same text as Task 1, Step 2) immediately after the closing `</governance_constraints>` tag and before the `{{committee_context}}` line:

```ruby
        <tone_calibration>
        - Match editorial intensity to the stakes. High-impact decisions (major
          rezonings, large contracts, tax changes) deserve more scrutiny than
          routine approvals.
        - Use direct, accurate language — not loaded characterizations:
          - "claims" (when the city projects future benefits), not "pitched as"
            or "sold as"
          - "no one spoke at the public hearing" not "quietly" or "with limited
            scrutiny" — then note whether low engagement is surprising given
            the stakes
          - "passed unanimously" not "green-lit" or "rubber-stamped"
          - State implications directly: "the rezoning expands allowed uses to
            include retail and housing" — not "opens the door" or speculative
            scenarios about what might happen later
        - Low public engagement on high-stakes items is worth noting as an
          observation — but remember that in a small city, residents may not
          engage because of social capital costs, belief that input won't matter,
          or simply not tracking the issue. Don't assume silence means satisfaction
          and don't assume it means the decision was sneaked through.
        - Cross-body movement (committee recommends, council approves) is normal
          workflow and not noteworthy. Only flag cross-body patterns when council
          sends a topic back to committee or when a topic bounces repeatedly
          between bodies without resolution.
        </tone_calibration>
```

- [ ] **Step 3: Verify the prompt template loads**

Run: `bin/rails runner "puts PromptTemplateData::TEMPLATES['analyze_topic_summary'][:instructions][0..200]"`

Expected: prints updated instructions without error.

- [ ] **Step 4: Commit**

```bash
git add lib/prompt_template_data.rb
git commit -m "feat: calibrate analyze_topic_summary tone — framing instruction, tone block"
```

---

### Task 3: Update `analyze_meeting_content` prompt — system role and tone calibration

**Files:**
- Modify: `lib/prompt_template_data.rb:736-788`

- [ ] **Step 1: Replace the system role**

In `lib/prompt_template_data.rb`, replace the `analyze_meeting_content` system_role (lines 736-746):

```ruby
    "analyze_meeting_content" => {
      system_role: <<~ROLE.strip,
        You are a civic journalist covering Two Rivers, WI city government
        for a community news site. Your audience is residents — mostly 35+,
        mobile-heavy, checking in casually.
        They want the gist fast in plain language. No government jargon.

        Write in editorial voice: skeptical of process and decisions (not of
        people), editorialize early when the stakes warrant it, surface
        patterns when the record supports them. Criticize decisions and
        processes, not individuals. Match your editorial intensity to the
        stakes — routine business gets factual treatment, high-impact decisions
        get more scrutiny.
      ROLE
```

Changes: removed "skeptical of city leadership" from audience description. Replaced "flag when framing doesn't match outcomes" with "when the stakes warrant it" / "when the record supports them." Added intensity-matching guidance.

- [ ] **Step 2: Add tone_calibration block to instructions**

Add the `<tone_calibration>` block (same text as Task 1, Step 2) immediately after the closing `</procedural_filter>` tag (line 788) and before the `DOCUMENT TEXT:` line:

```ruby
        <tone_calibration>
        - Match editorial intensity to the stakes. High-impact decisions (major
          rezonings, large contracts, tax changes) deserve more scrutiny than
          routine approvals.
        - Use direct, accurate language — not loaded characterizations:
          - "claims" (when the city projects future benefits), not "pitched as"
            or "sold as"
          - "no one spoke at the public hearing" not "quietly" or "with limited
            scrutiny" — then note whether low engagement is surprising given
            the stakes
          - "passed unanimously" not "green-lit" or "rubber-stamped"
          - State implications directly: "the rezoning expands allowed uses to
            include retail and housing" — not "opens the door" or speculative
            scenarios about what might happen later
        - Low public engagement on high-stakes items is worth noting as an
          observation — but remember that in a small city, residents may not
          engage because of social capital costs, belief that input won't matter,
          or simply not tracking the issue. Don't assume silence means satisfaction
          and don't assume it means the decision was sneaked through.
        - Cross-body movement (committee recommends, council approves) is normal
          workflow and not noteworthy. Only flag cross-body patterns when council
          sends a topic back to committee or when a topic bounces repeatedly
          between bodies without resolution.
        </tone_calibration>
```

- [ ] **Step 3: Verify the prompt template loads**

Run: `bin/rails runner "puts PromptTemplateData::TEMPLATES['analyze_meeting_content'][:system_role]"`

Expected: prints the updated system role without "flag when framing doesn't match outcomes."

- [ ] **Step 4: Commit**

```bash
git add lib/prompt_template_data.rb
git commit -m "feat: calibrate analyze_meeting_content tone — system role, tone block"
```

---

### Task 4: Update AUDIENCE.md — editorial voice and resident disposition

**Files:**
- Modify: `docs/AUDIENCE.md:83-90` (editorial voice)
- Modify: `docs/AUDIENCE.md:180-193` (resident disposition)

- [ ] **Step 1: Add "Silence" bullet after "Editorialize early"**

In `docs/AUDIENCE.md`, insert a new bullet after the "Editorialize early" bullet (after line 86, before the "Means to an end" bullet):

```markdown
- **Silence is not one thing.** In a small city where social capital and
  reputation matter, low public engagement may reflect satisfaction,
  resignation, social pressure, or simply not knowing. Note low
  engagement on high-stakes items as an observation, not as an
  indictment of process.
```

- [ ] **Step 2: Replace the "Means to an end" bullet**

Replace lines 87-90:

```markdown
- **"Means to an end" analysis is fair game.** Pointing out that a
  decision benefits developers at the expense of residents, or that
  official rationale doesn't match observable effects, is useful
  analysis. But use direct, factual language — not loaded
  characterizations. "The rezoning expands allowed uses" not "opens
  the door." "The city claims $50K in savings" not "sold as savings."
  Let the facts carry the editorial weight. Saying someone is acting
  in bad faith is never appropriate.
```

- [ ] **Step 3: Replace the Resident Disposition section**

Replace lines 182-193 (the bullet list under "### Resident Disposition"):

```markdown
Two Rivers residents tend to:

- Be skeptical of city leadership, both elected officials and appointed
  staff — this is the lens they bring, and analysis should be aware of it
- Feel that decisions are often made before public input is genuinely
  considered — whether or not that's true in a given case, it shapes how
  residents receive information
- Pay close attention to who benefits from development and spending
  decisions
- Value stability and preservation over growth and change — many did not
  choose the city's shift toward tourism
- Have strong opinions about downtown character and lakefront use
- Be cautious about public engagement — reputation and social capital
  discourage public criticism even when residents have strong private
  concerns
- Engage most actively when proposed changes affect their neighborhoods
  directly
```

- [ ] **Step 4: Commit**

```bash
git add docs/AUDIENCE.md
git commit -m "docs: calibrate AUDIENCE.md editorial voice and resident disposition"
```

---

### Task 5: Update TOPIC_GOVERNANCE.md — Section 6 silence nuance

**Files:**
- Modify: `docs/topics/TOPIC_GOVERNANCE.md:179`

- [ ] **Step 1: Add nuance after "Silence is not neutral."**

In `docs/topics/TOPIC_GOVERNANCE.md`, after line 179 ("Silence is not neutral."), insert:

```markdown

However, silence has multiple possible explanations, especially in a
small social-capital community. The LLM must not default to treating
silence as evidence of secrecy or exclusion. Low engagement on
high-impact items is worth noting as an observation — but the cause
is often unknowable from the record alone.
```

- [ ] **Step 2: Commit**

```bash
git add docs/topics/TOPIC_GOVERNANCE.md
git commit -m "docs: add silence nuance to TOPIC_GOVERNANCE.md section 6"
```

---

### Task 6: Update community context seed — resident disposition reframe

**Files:**
- Modify: `db/seeds/community_context.rb:44-50`

- [ ] **Step 1: Replace the Resident Disposition bullet list**

In `db/seeds/community_context.rb`, replace lines 44-50:

```ruby
  Two Rivers residents tend to:
  - Be skeptical of city leadership, both elected officials and appointed staff — this is the lens they bring, and analysis should be aware of it
  - Feel that decisions are often made before public input is genuinely considered — whether or not that's true in a given case, it shapes how residents receive information
  - Pay close attention to who benefits from development and spending decisions
  - Value stability and preservation over growth and change — many did not choose the city's shift toward tourism
  - Have strong opinions about downtown character and lakefront use
  - Be cautious about public engagement — reputation and social capital discourage public criticism even when residents have strong private concerns
  - Engage most actively when proposed changes affect their neighborhoods directly
```

- [ ] **Step 2: Commit**

```bash
git add db/seeds/community_context.rb
git commit -m "feat: reframe community context resident disposition as context, not posture"
```

**Note:** The seed file only affects new database setups. To update the existing KnowledgeSource record in the database, run:

```bash
bin/rails runner "
source = KnowledgeSource.find_by(title: 'Two Rivers Community Context — Topic Extraction Guide')
if source
  source.update!(body: COMMUNITY_CONTEXT_BODY)
  puts 'Updated. Run IngestKnowledgeSourceJob.perform_now(#{source.id}) to re-embed.'
end
"
```

This is a manual post-deploy step, not an automated migration.

---

### Task 7: Update helper and tests — backward-compatible process_concerns rendering

**Files:**
- Modify: `app/helpers/topics_helper.rb:78-80`
- Modify: `test/helpers/topics_helper_test.rb:129-139`
- Modify: `test/controllers/topics_controller_test.rb:300,324,361`
- Modify: `test/jobs/topics/generate_topic_briefing_job_test.rb:34`

- [ ] **Step 1: Write failing test for string format**

In `test/helpers/topics_helper_test.rb`, add a new test after line 139:

```ruby
  test "briefing_process_concerns handles string format from new schema" do
    briefing = OpenStruct.new(generation_data: {
      "editorial_analysis" => { "process_concerns" => "Topic deferred 3 times without explanation." }
    })
    assert_equal [ "Topic deferred 3 times without explanation." ], briefing_process_concerns(briefing)
  end

  test "briefing_process_concerns handles null from new schema" do
    briefing = OpenStruct.new(generation_data: {
      "editorial_analysis" => { "process_concerns" => nil }
    })
    assert_equal [], briefing_process_concerns(briefing)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/helpers/topics_helper_test.rb -n "/process_concerns handles/"`

Expected: 2 failures. The string test will fail because the current helper returns the raw string, not a wrapped array. The nil test may pass since `nil || []` returns `[]`.

- [ ] **Step 3: Update the helper**

In `app/helpers/topics_helper.rb`, replace lines 78-80:

```ruby
  def briefing_process_concerns(briefing)
    value = briefing&.generation_data&.dig("editorial_analysis", "process_concerns")
    case value
    when Array then value
    when String then [ value ]
    else []
    end
  end
```

- [ ] **Step 4: Run all process_concerns tests**

Run: `bin/rails test test/helpers/topics_helper_test.rb -n "/process_concerns/"`

Expected: all 4 tests pass (2 existing + 2 new).

- [ ] **Step 5: Run full helper test file**

Run: `bin/rails test test/helpers/topics_helper_test.rb`

Expected: all tests pass.

- [ ] **Step 6: Run topics controller tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb`

Expected: all pass. The controller fixtures use arrays which still work with the updated helper.

- [ ] **Step 7: Run briefing job tests**

Run: `bin/rails test test/jobs/topics/generate_topic_briefing_job_test.rb`

Expected: all pass. The job test fixture uses an empty array which still works.

- [ ] **Step 8: Commit**

```bash
git add app/helpers/topics_helper.rb test/helpers/topics_helper_test.rb
git commit -m "feat: handle string/null process_concerns for new prompt schema"
```

---

### Task 8: Run full test suite and lint

- [ ] **Step 1: Run full test suite**

Run: `bin/rails test`

Expected: all tests pass.

- [ ] **Step 2: Run RuboCop**

Run: `bin/rubocop`

Expected: no new offenses.

- [ ] **Step 3: Run CI**

Run: `bin/ci`

Expected: all checks pass.

- [ ] **Step 4: Fix any issues**

If any tests fail or lint issues appear, fix them and re-run.

- [ ] **Step 5: Commit any fixes**

Only if fixes were needed in step 4.

---

### Task 9: Sync prompt templates to database

The prompt templates in `lib/prompt_template_data.rb` are the source of truth, but the database has its own copies. After all code changes are committed, sync the updated prompts.

- [ ] **Step 1: Sync prompt templates**

Run: `bin/rails runner "PromptTemplate.find_each { |pt| data = PromptTemplateData::TEMPLATES[pt.slug]; next unless data; pt.update!(system_role: data[:system_role], instructions: data[:instructions]) }; puts 'Done'"`

Expected: prints "Done" — updates the 3 changed templates in the database.

- [ ] **Step 2: Verify the changed templates**

Run: `bin/rails runner "['analyze_topic_briefing', 'analyze_topic_summary', 'analyze_meeting_content'].each { |s| pt = PromptTemplate.find_by(slug: s); puts \"#{s}: #{pt.instructions.include?('tone_calibration')}\" }"`

Expected: all three print `true`.

- [ ] **Step 3: Update the community context KnowledgeSource**

Run: `bin/rails runner "load 'db/seeds/community_context.rb'"`

This will print "Community context KnowledgeSource already exists" because the record exists. To update the existing record with the new text:

Run: `bin/rails runner "load 'db/seeds/community_context.rb'; source = KnowledgeSource.find_by(title: COMMUNITY_CONTEXT_TITLE); source.update!(body: COMMUNITY_CONTEXT_BODY); IngestKnowledgeSourceJob.perform_now(source.id); puts 'Updated and re-embedded.'"`

Expected: prints "Updated and re-embedded."

---

### Task 10: Verification — regenerate meeting 136 summary and compare

- [ ] **Step 1: Regenerate the meeting 136 summary**

Run: `bin/rails runner "SummarizeMeetingJob.perform_now(136)"`

Expected: completes without error.

- [ ] **Step 2: Read the new output**

Run: `bin/rails runner "m = Meeting.find(136); ms = m.meeting_summaries.last; puts ms.generation_data.to_json"`

- [ ] **Step 3: Compare against design spec criteria**

Check that the new output:
- Does NOT use "quietly," "pitched as," "sold as," "green-lit," "rubber-stamped," or similar loaded characterizations
- Notes the Hamilton rezoning's low public engagement factually, with appropriate editorial weight
- Describes the IT contract's cost claims as "claims" without implying a sales job
- Does NOT fabricate hypothetical future scenarios
- Treats the closed session as standard legal process
- Still surfaces who is affected by decisions and notes patterns when supported
