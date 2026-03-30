# Editorial Tone Calibration Design

**Date:** 2026-03-29
**Problem:** AI analysis fabricates adversarial narratives when source material doesn't support them

## Problem Statement

The AI analysis prompts produce output that crosses the line from healthy skepticism into fear, uncertainty, and doubt (FUD). The substance is often directionally correct, but the language implies nefariousness where the evidence doesn't warrant it.

### Observed failure modes

From meeting 136 (City Council):

- **"quietly green-lit"** — An 8-0 vote after a public hearing. The AI interpreted "no public comment" as sneaky rather than "nobody objected."
- **"with limited public scrutiny"** — An 8-0 vote on an $80K/year IT contract. Normal city business characterized as secretive.
- **"sold as savings" / "pitched as"** — The city's cost projections characterized as a sales job rather than claims to be evaluated.
- **"when the real project shows up and residents are told the zoning already allows it"** — A fabricated future scare scenario to make a routine rezoning sound sinister.
- **"residents are left to trust"** — Closed session per state statute described as a transparency concern when it's the legal framework working as designed.

### Pattern

The AI treats the absence of controversy as itself suspicious. No public comment becomes "quietly." Unanimous votes become evidence of insufficient scrutiny. Normal process becomes "framing." When it can't find an actual concern, it invents a hypothetical future one. Each statement technically complies with the "don't ascribe bad intent" guardrail, but the cumulative effect is FUD.

### Root causes

1. **Array fields pressure the AI to produce content.** `process_concerns` and `pattern_observations` as arrays invite filling. 76 of 77 existing briefings have non-empty `process_concerns` — the AI almost never returns an empty array.
2. **No guidance normalizing routine outcomes.** Prompts have extensive guidance for how to be skeptical but nothing that says most government business is routine.
3. **"Framing" language delegitimizes all official rationale.** "Label staff summaries/titles as framing, not truth" makes every staff explanation sound like spin.
4. **Loaded characterizations.** The prompts don't distinguish between surfacing valid concerns (good) and characterizing them with dramatic language (bad).
5. **Community context primes suspicion.** "Residents are skeptical of city leadership" and "feel decisions are made before input is considered" — injected into every analysis call — tell the AI the default posture should be suspicion.
6. **Cross-body movement over-flagged.** Normal committee→council flow treated as a signal alongside actually-meaningful repeated bouncing.

### What is NOT the problem

- The skeptical lens itself — that's the product's value proposition
- The AI's ability to infer who benefits, connect dots across timelines, note when engagement is surprisingly low — all essential
- The epistemic structure (fact/framing/sentiment) in TOPIC_GOVERNANCE.md — sound
- The knowledge base gap (incomplete KB, no feedback loop) — real but separate workstream

## Core Principle

**The skepticism is in what you choose to surface, not in how you characterize it.**

Match editorial intensity to the stakes. State what happened. State the implications. Use direct, factual language. Let the reader decide how to feel about it.

The AI should absolutely infer, connect dots, and note concerning patterns. It should do so with accurate, direct language rather than loaded characterizations that imply nefariousness.

## Changes

### 1. New `<tone_calibration>` constraint block — all analysis prompts

Added to `analyze_topic_briefing`, `analyze_meeting_content`, and `analyze_topic_summary`.

```
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

### 2. `analyze_topic_briefing` — schema and voice changes

**`process_concerns`** — change from array to nullable string:

```
# Before
"process_concerns": ["Process red flags, if any — keep brief"]

# After
"process_concerns": "A specific, concrete process issue if one exists
  (e.g., topic deferred 3+ times, public hearing requirement skipped,
  repeated send-backs between bodies without resolution). Null for most
  topics — routine government process is not a concern, and a null
  field is expected."
```

**`pattern_observations`** — reword description:

```
# Before
"pattern_observations": ["Short observations about patterns, if any"]

# After
"pattern_observations": ["Observations about patterns when supported by
  the timeline — repeated deferrals, topic disappearing without
  resolution, repeated bouncing between bodies. Empty array is normal
  and expected for most topics."]
```

**Voice section** — replace "Note who benefits" line:

```
# Before
- Note who benefits from decisions when relevant.

# After
- Note who is affected by decisions and how. You can infer this from
  context, knowledgebase, public comment, and patterns over time — it
  won't be stated explicitly in city documents.
```

**Constraints section** — add:

```
- Most government business is routine. A null process_concerns and an
  empty pattern_observations array reflect good analysis, not a gap.
```

### 3. `analyze_topic_summary` — soften framing instruction

```
# Before
- Institutional Framing: Label staff summaries/titles as framing, not truth.

# After
- Institutional Framing: Staff summaries and agenda titles reflect the
  city's perspective — note them as such. They may be accurate, incomplete,
  or self-serving depending on context. Don't default to treating them as
  spin, but don't accept them uncritically either.
```

### 4. `analyze_meeting_content` — system role

```
# Before
Write in editorial voice: skeptical of process and decisions (not of
people), editorialize early, surface patterns, note deferrals, flag
when framing doesn't match outcomes. Criticize decisions and
processes, not individuals.

# After
Write in editorial voice: skeptical of process and decisions (not of
people), editorialize early when the stakes warrant it, surface
patterns when the record supports them. Criticize decisions and
processes, not individuals. Match your editorial intensity to the
stakes — routine business gets factual treatment, high-impact decisions
get more scrutiny.
```

### 5. AUDIENCE.md — Editorial Voice section

**"Means to an end" paragraph:**

```
# Before
- **"Means to an end" analysis is fair game.** Pointing out that a
  decision benefits developers at the expense of residents, or that
  safety framing is being used to justify changes with other effects, is
  useful analysis. Saying someone is acting in bad faith is not.

# After
- **"Means to an end" analysis is fair game.** Pointing out that a
  decision benefits developers at the expense of residents, or that
  official rationale doesn't match observable effects, is useful
  analysis. But use direct, factual language — not loaded
  characterizations. "The rezoning expands allowed uses" not "opens
  the door." "The city claims $50K in savings" not "sold as savings."
  Let the facts carry the editorial weight. Saying someone is acting
  in bad faith is never appropriate.
```

**New bullet after "Editorialize early":**

```
- **Silence is not one thing.** In a small city where social capital and
  reputation matter, low public engagement may reflect satisfaction,
  resignation, social pressure, or simply not knowing. Note low
  engagement on high-stakes items as an observation, not as an
  indictment of process.
```

### 6. TOPIC_GOVERNANCE.md — Section 6, add nuance

After the existing "Silence is not neutral." sentence:

```
However, silence has multiple possible explanations, especially in a
small social-capital community. The LLM must not default to treating
silence as evidence of secrecy or exclusion. Low engagement on
high-impact items is worth noting as an observation — but the cause
is often unknowable from the record alone.
```

### 7. Community context — Resident Disposition reframe

Appears in both `db/seeds/community_context.rb` and the "Community Context" section of `docs/AUDIENCE.md`.

```
# Before
Two Rivers residents tend to:
- Be skeptical of city leadership, both elected officials and appointed staff
- Feel that decisions are often made before public input is genuinely considered
- Pay close attention to who benefits from development and spending decisions
- Value stability and preservation over growth and change
- Have strong opinions about downtown character and lakefront use
- Engage most actively when proposed changes affect their neighborhoods directly

# After
Two Rivers residents tend to:
- Be skeptical of city leadership, both elected officials and appointed
  staff — this is the lens they bring, and analysis should be aware of it
- Feel that decisions are often made before public input is genuinely
  considered — whether or not that's true in a given case, it shapes how
  residents receive information
- Pay close attention to who benefits from development and spending decisions
- Value stability and preservation over growth and change — many did not
  choose the city's shift toward tourism
- Have strong opinions about downtown character and lakefront use
- Be cautious about public engagement — reputation and social capital
  discourage public criticism even when residents have strong private concerns
- Engage most actively when proposed changes affect their neighborhoods directly
```

The key change: the first two bullets now frame resident disposition as *context the AI should understand* rather than *a posture the AI should adopt*.

### 8. Rendering changes for `process_concerns` schema change

**`app/helpers/topics_helper.rb`** — update `briefing_process_concerns` to handle both old (array) and new (string/nil) data:

```ruby
def briefing_process_concerns(briefing)
  value = briefing&.generation_data&.dig("editorial_analysis", "process_concerns")
  case value
  when Array then value  # legacy data
  when String then [value] # new format — wrap for view compat
  else []
  end
end
```

The view template (`topics/show.html.erb`) already guards on `concerns.any?` and renders as `<li>` items — no view changes needed.

**Tests** — update helper tests and controller test fixtures.

### 9. What is NOT changing

- **TOPIC_GOVERNANCE.md core principles** — epistemic structure, prohibited behaviors, pattern recognition. All sound.
- **Knowledge base architecture** — the KB population gap and feedback loop are a separate workstream.
- **Two-pass briefing architecture** — no pipeline changes.
- **Resident impact scoring rubric** — no changes.
- **The skeptical lens itself** — the product's value is surfacing what residents wouldn't otherwise see. That stays.

## Files affected

| File | Change type |
|------|------------|
| `lib/prompt_template_data.rb` | Prompt text: `analyze_topic_briefing`, `analyze_topic_summary`, `analyze_meeting_content` |
| `docs/AUDIENCE.md` | Editorial voice calibration, community context disposition |
| `docs/topics/TOPIC_GOVERNANCE.md` | Section 6 nuance on silence |
| `db/seeds/community_context.rb` | Resident disposition reframe |
| `app/helpers/topics_helper.rb` | Handle string/nil `process_concerns` |
| `test/helpers/topics_helper_test.rb` | Update helper tests |
| `test/controllers/topics_controller_test.rb` | Update fixtures |
| `test/jobs/topics/generate_topic_briefing_job_test.rb` | Update fixtures |

## Verification

After implementation, regenerate the meeting 136 summary and compare output against the current version. The new output should:

- Not use "quietly," "pitched as," "sold as," "green-lit," "rubber-stamped," or similar loaded characterizations
- Note the Hamilton rezoning's low public engagement factually, with appropriate editorial weight for a high-impact item
- Describe the IT contract's cost claims as "claims" without implying a sales job
- Not fabricate hypothetical future scenarios
- Treat the closed session as standard legal process, not a transparency concern
- Still surface who is affected by decisions and note patterns when the record supports them
