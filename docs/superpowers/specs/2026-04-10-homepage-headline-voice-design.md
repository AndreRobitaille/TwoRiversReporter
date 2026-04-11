# Homepage Headline Voice

**Date:** 2026-04-10
**Status:** Draft
**Scope:** `analyze_topic_briefing` prompt template (both database copy and `lib/prompt_template_data.rb` source)

## Problem

The homepage currently shows twelve topic cards whose headlines read as meta-commentary about the agenda process rather than news residents would click. Seven of twelve end with banned-closer filler like *"vote not reported yet"*, *"keeps coming back"*, or *"still no clear decision"*. Several use quoted jargon (*"contract execution concerns"*, *"TIF talk"*) that the model couldn't translate. Others manufacture process concerns that the underlying analysis doesn't support (*"where it'll happen is still unclear"*).

A representative sample of what's live today:

- *Lead service line work is moving into big 2026 contracts, but "contract execution concerns" are now on the table.*
- *City put 0% borrowing on the table for water plant generator repairs and security upgrades. No vote has been reported yet.*
- *City is moving toward a $40,000 pilot to grind down sidewalk trip hazards. Where it'll happen is still unclear.*
- *Garbage and recycling changes keep coming back to committee agendas. Still no clear decision reported.*

Root cause: the `analyze_topic_briefing` prompt's `headline` field spec says *"Backward-looking: what just happened or where things stand"*, which invites status updates. When the analysis has no hard news beat, the model falls back to describing the topic's own recurrence pattern, producing the "keeps coming back, vote not reported yet" voice. The prompt never tells the model what the Two Rivers audience wants from a headline, and never forbids the specific filler phrases.

## Solution

Rewrite the `analyze_topic_briefing` prompt's `instructions` field to add:

1. A **`<headline_criteria>`** block with ten explicit rules for the `headline`, `upcoming_headline`, and `editorial_analysis.current_state` fields. The rules enforce: lead with a specific concrete detail, 20-word limit for headlines, translate jargon, ban specific closer phrases, forbid manufactured process concerns, forbid asserted causality without support, forbid adjectives of outrage, forbid quoted jargon. Includes good/bad examples tied to real Two Rivers topics.

2. A **`<voice_scope>`** block that explicitly scopes the audience voice to exactly three fields (`headline`, `upcoming_headline`, `editorial_analysis.current_state`) and marks every other field as NEUTRAL with field-level reminders. This is the bleed fence — it prevents the audience voice from leaking into `factual_record`, `civic_sentiment`, `pattern_observations`, `process_concerns`, and the rest of the evidence-load-bearing fields.

3. Expanded jargon translation examples in the existing `<voice>` block (TID → TIF district, saw-cut → grind down, revenue bond → rate-backed loan, enterprise fund → utility fund, conditional use permit → zoning variance, certified survey map → lot subdivision).

4. A `NEUTRAL.` annotation prefix on every non-voice field in `<extraction_spec>` as a third layer of defense against bleed.

The `system_role` is not changed. The rest of the prompt (`<tone_calibration>`, `<constraints>`, `{{committee_context}}`, `{{context}}`, the overall JSON schema shape) is preserved. The model is still `gpt-5.2` (DEFAULT_MODEL), temperature `0.1`, `response_format: { type: "json_object" }`.

### Design decisions that shaped this

**Aim for the headline voice: Option C with a tinge of B and subliminal A.** The headline's job is to name a stake residents already recognize (C), deliver enough news that the scanner is informed even if they don't click (B), and tap the audience's existing priors quietly (A — never shouting, never on-the-nose). The Bernays move is legitimate only when the underlying facts support the implication.

**Accuracy always wins.** A boring-but-accurate headline is survivable; an inaccurate headline that implies impropriety destroys trust with a skeptical audience. When these pull against each other, the prompt picks accuracy. Rules 7 and 8 (banned manufactured process concerns and banned asserted causality) are the structural guarantees — the headline may only combine facts the analysis presents as connected, and may not imply a process problem unless `process_concerns` independently supports one.

**Scope extends to `editorial_analysis.current_state` (Option B).** The headline and the opening paragraph of "The Story" on the topic page should feel like the same product. Restricting the voice only to the headline would leave the topic-page opener in the old status-update voice, creating a jarring tonal gap when the reader clicks. Extending to the full `editorial_analysis` sub-object was rejected because `pattern_observations` and `process_concerns` have evidence-bound rules that audience voice could corrupt.

**Bleed fence by construction, not by instruction alone.** The `<voice_scope>` block names the three allowed fields explicitly and lists every other field with a NEUTRAL annotation. Additionally, each neutral field in `<extraction_spec>` gets a `NEUTRAL.` prefix in its description. Three layers: scoping block, constraints reminder, field-level annotations. Validated against four real topics — zero bleed detected.

## Validation

A one-off script at `tmp/headline_validation.rb` (runnable via `bin/rails runner tmp/headline_validation.rb`) calls OpenAI twice per topic with identical context (same system_role, same committee_context, same briefing context JSON, same model, same temperature) — once with the current database `instructions`, once with the new `instructions`. Four topics: lead service lines, water filtration plant backup power, tax increment financing, sidewalk trip hazard repairs. Two iterations were run during brainstorming.

### Iteration 2 results (current state)

| Topic | OLD headline | NEW headline |
|---|---|---|
| Lead service lines | *Lead service line work keeps moving, but key votes and fixes aren't publicly clear yet.* | **$2.44 million lead water service replacements target Two Rivers' near north side in 2026** |
| Water plant backup power | *City put a 0% borrowing plan on the table for water plant backup power and security work.* | **$496,676 at 0%: borrowing for water plant generator repairs and security upgrades** |
| Tax increment financing | *City moved toward ending two TIF districts early and using TIF money for motel and inn upgrades. Votes not reported yet.* | **Up to $27,536 in TIF district money for Cool City Motel doors and Lighthouse Inn lighting/signs** |
| Sidewalk trip hazards | *City is moving toward a $40,000 sidewalk trip-hazard pilot. The "2026 Sidewalk Program" details still aren't public.* | **$40,000 pilot to grind down sidewalk trip hazards is up for approval** |

All four NEW headlines lead with a specific concrete detail, stay under 20 words, use no banned closers, translate all jargon (no "TID", no "saw-cut"), and assert no causality without analytical support. The iteration-2 TIF headline was verified against source materials — the $27,536 (= $17,536 + $10,000) and the specific businesses are present in meeting 155's agenda item summaries; the model did not hallucinate.

### Bleed check: passed

| Field | Result |
|---|---|
| `process_concerns` | NEW was null on all 4 topics. OLD had thin process concerns on 3 of 4 that were really just "agenda language is high-level" observations — exactly the upstream cause of the old manufactured-tension headlines. The stricter bar eliminates these. |
| `pattern_observations` | Same count or fewer, evidence-bound in all cases. |
| `factual_record` | Still dry, observational, no framing. NEW was slightly drier than OLD on multiple topics. |
| `civic_sentiment` | Empty in both (underlying data has none). |
| `resident_impact.rationale` | Both neutral. Scores matched on 3/4 topics (lead service lines dropped 5→4, within normal variation). |

The three-layer bleed fence held. The audience voice did not leak into any evidence-load-bearing field.

### Pre-deploy validation required

Before flipping the production prompt, run one more validation pass against 3–4 **structurally different** topics — ones with very different context shapes than the iteration-1/2 set. Candidates: garbage and recycling service changes (thin content, was a "keeps coming back" offender), fee schedule (also thin), wisconsin DNR grant (high-context, low-impact), a topic with populated `civic_sentiment` if one can be found (tests whether the new voice leaks when there IS data for that field). If any of those surface bleed or hallucination, iterate the prompt once more before deploy.

## Changes

### 1. Database `PromptTemplate` record (`key: "analyze_topic_briefing"`)

Edit the template's `instructions` field via `/admin/prompt_templates`. The admin UI auto-creates a `PromptVersion` on save, which is the rollback path if the change regresses in production.

The new `instructions` value is the full text in **Appendix A** at the end of this spec. It preserves `{{committee_context}}` and `{{context}}` placeholders verbatim so `PromptTemplate#interpolate` continues to work without code changes. (During brainstorming the same text lived in `tmp/headline_validation.rb` as the `NEW_INSTRUCTIONS` HEREDOC constant; that file is gitignored and is a temporary working copy, not the canonical source.)

Key structural differences vs. the current `instructions`:

- **Expanded `<voice>` jargon examples.** Four new mappings added:
  - `TID` / `T.I.D.` → `TIF district` (always spell out)
  - `saw-cut` / `saw-cutting` → `shave down` or `grind down the raised edges`
  - `conditional use permit` → `zoning variance`
  - `certified survey map` → `lot subdivision`
  - Existing `revenue bond` → `rate-backed loan` and `enterprise fund` → `utility fund` added alongside existing `general obligation promissory notes`, `land disposition`, `parameters` examples.

- **New bullet in `<constraints>`** explicitly scoping the voice rules to three fields and listing every other field that must remain neutral.

- **New `<voice_scope>` block** placed after `{{context}}` and before `<extraction_spec>`. Lists the three fields where audience voice applies. Lists every other field with a short neutral-behavior spec. Includes the explicit rule *"DO NOT retrofit a process_concern to justify a more interesting headline — the headline and the process_concerns field must be independently supported by the data."*

- **New `<headline_criteria>` block** placed after `<voice_scope>` and before `<extraction_spec>`. Ten rules:
  1. Lead with the most specific concrete detail in the analysis.
  2. 20-word max for headlines, 1–3 sentences for `current_state`.
  3. Translate all jargon (with examples).
  4. Name a stake a resident recognizes (cost, street, rates, neighborhood, who benefits).
  4a. When multiple concrete details compete, prefer resident-proximate (street, walk, cost) over implementation mechanism (contractor, technique). Only lead with mechanism when the mechanism IS the story (e.g., 0% financing).
  5. Interesting-ness comes from specificity, not from framing.
  6. Banned closers (explicit list): "No vote has been reported yet", "Vote unclear", "Still pending", "Still no clear decision", "Keeps coming back", "Keeps circling", "Keeps popping up", "Contract execution concerns", "Discussion expected".
  7. No manufactured process concerns — forbidden second-beat phrases ("picked before the vote", "hasn't been spelled out", "hasn't been released", "now a question", "nobody has said", "still not clear why") unless `process_concerns` or `pattern_observations` explicitly supports them.
  8. No asserted causality or sequence — connectors "so", "to fund", "in order to", "because", "after", "before" require direct textual support in the analysis.
  9. No adjectives of outrage ("shocking", "controversial", "wasteful", "rushed", "sneaky", "rubber-stamped", "green-lit", "sold as", "pitched as").
  10. No quoted jargon — if reaching for quotation marks, translate instead.

  Rules 5, 7, 8 are the accuracy guardrails. Rule 4a is the press-release guardrail.

  Includes six GOOD examples and six BAD examples tied to real Two Rivers topics, each with a reason explaining the failure mode.

- **`<extraction_spec>` schema annotations.** Every non-voice field gets a `NEUTRAL.` prefix in its description. The `headline`, `upcoming_headline`, and `editorial_analysis.current_state` fields reference `<headline_criteria>` instead of spelling out inline rules. `process_concerns` gets the additional annotation *"DO NOT populate this field to justify a more interesting headline — it must be independently supported by the source data."*

The full text of the new `instructions` is in **Appendix A** of this spec. When the implementation plan runs, that text becomes the canonical value in two places: the database (via admin UI) and `lib/prompt_template_data.rb` (for fresh installs).

### 2. `lib/prompt_template_data.rb`

The `"analyze_topic_briefing"` entry's `instructions:` HEREDOC is replaced with the new text. This is the source-of-truth for fresh installs and for any future `prompt_templates:populate` run. The `system_role:` field is not changed. The entry's metadata (key, name, description, usage_context, model_tier, placeholders) is not changed.

**No migration needed** — `PromptTemplate#after_save` handles versioning automatically when the admin edit happens, and fresh installs get the new text from the rake task.

### 3. No other code changes

- `Ai::OpenAiService#analyze_topic_briefing` — no changes. Still calls `PromptTemplate.find_by!(key: "analyze_topic_briefing")`, interpolates, posts to OpenAI with the same parameters.
- `Topics::GenerateTopicBriefingJob` — no changes. Still builds context the same way, still calls `analyze_topic_briefing`, still parses the JSON, still saves to `TopicBriefing`.
- `HomeController` — no changes. Still pulls `TopicBriefing.headline` via `load_headlines`.
- `TopicsHelper` — no changes. Still renders `current_state` from `generation_data`.

This is a pure prompt edit. The contract between the database record and the calling code is unchanged.

## Rollout

1. **Edit the database prompt via admin UI** at `/admin/prompt_templates`, selecting the "Topic Briefing Analysis" template. Paste the new `instructions` text. Save — this creates a `PromptVersion` row automatically.
2. **Update `lib/prompt_template_data.rb`** in the same commit so fresh installs get the new text.
3. **Backfill existing `TopicBriefing` records** by re-running `Topics::GenerateTopicBriefingJob` for every topic that currently shows on the homepage and the topic index. A rake task or a one-off script is fine:
   ```ruby
   Topic.approved.where("last_activity_at > ?", 30.days.ago).find_each do |topic|
     meeting = topic.topic_appearances.joins(:meeting).order("meetings.starts_at DESC").first&.meeting
     Topics::GenerateTopicBriefingJob.perform_later(topic_id: topic.id, meeting_id: meeting.id) if meeting
   end
   ```
   Cost estimate: each briefing runs two OpenAI calls (pass 1 `analyze_topic_briefing` and pass 2 `render_topic_briefing`) at roughly $0.05 per call, so about $0.10 per topic. For 20–40 topics that's $2–$4 total.
4. **Spot-check the homepage** after the backfill completes. Confirm the twelve cards read with the new voice and no old "keeps coming back" filler remains.
5. **Rollback path** if the new prompt regresses in production: edit the template in `/admin/prompt_templates` and paste the previous version's text (available in the `prompt_versions` table). Re-run the backfill.

## Success Criteria

The change is successful if, after the backfill:

- No homepage headline ends with any phrase in the banned-closers list.
- No homepage headline contains quoted jargon (e.g., `"TIF talk"`, `"contract execution concerns"`).
- No homepage headline uses untranslated terms from the translation list (`TID`, `saw-cut`, `revenue bond`, `enterprise fund`, `conditional use permit`, `certified survey map`, `general obligation promissory notes`).
- At least 8 of 12 homepage headlines lead with a specific concrete detail (dollar amount, street name, named program, vote count, deadline, neighborhood).
- A manual review of 5 random `TopicBriefing.generation_data` records confirms `factual_record`, `civic_sentiment`, `pattern_observations`, and `process_concerns` still read as dry/observational — no editorial voice bleed.
- No briefing contains a fabricated date, dollar amount, or business name that cannot be traced to the source context (sampled by spot-checking against meeting documents).

## Explicitly Out of Scope

- **Homepage structural issues.** The current homepage shows six cards telling one story (the 2026 capital borrowing package split across lead service lines, water main, utility financing, water plant generators, sidewalk pilot, municipal borrowing). This will not be fixed by any prompt change — it's a structural deduplication problem that lives in `HomeController` or the topic-merging layer. Separate design effort.
- **Impact scores tied at 4.** Ten of twelve homepage topics currently have `resident_impact_score = 4`, which makes the Top Story / Wire Card / Wire Row tiering meaningless. The `id: :desc` tiebreaker is doing the real sorting. Fixing this requires either a more discriminating 1–5 scale in the prompt or a different scoring signal entirely. Out of scope for this prompt edit.
- **`upcoming_headline` returning null on every topic.** Both the OLD and NEW prompts returned `nil` for `upcoming_headline` on all four validation topics. This is a separate bug, likely in `GenerateTopicBriefingJob#build_upcoming_context` (which queries future meeting appearances). Separate investigation.
- **Interim / headline_only tier briefings.** `Topics::UpdateTopicBriefingJob` and the `generate_briefing_interim` prompt template generate lighter briefings for less-active topics. Those use a different prompt and are not touched by this change. If they produce poor headlines after this deploy, a follow-up pass can extend the same voice rules to that prompt.
- **Meeting summary headlines.** `analyze_meeting_content` generates a separate `headline` field for meeting-level summaries. That prompt is not touched here. Its failure modes and audience priorities may overlap but are not identical.
- **Topic summary rendering.** `analyze_topic_summary` and `render_topic_summary` produce per-meeting snapshot summaries, not rolling briefings. Not touched here.
- **Admin UI changes.** No new admin features. The existing `/admin/prompt_templates` interface is sufficient for the edit and for rollback.
- **Automated tests for prompt output quality.** Prompt output quality is not easily unit-testable. The validation mechanism is the runner script (`tmp/headline_validation.rb`), run manually during spec iteration and again before deploy. No CI gate for prompt quality is proposed.

## Risks

**R1: Overfitting to four topics.** The iteration 1 and 2 validation used the same four topics throughout. The new prompt may behave well on those four and poorly on structurally different topics. Mitigation: the pre-deploy validation step (run the script against 3–4 different topics before flipping production). If overfit is detected, one more iteration on the prompt before deploy.

**R2: Stricter process_concerns bar suppresses legitimate concerns.** The new bar eliminates "agenda language is high-level" as a valid process_concern. A real process concern — e.g., a topic deferred four times in a row — might still be missed if the model reads the stricter bar too literally. Mitigation: the bar examples in the new prompt explicitly list the legitimate cases (deferrals 3+ times, skipped public hearing, repeated send-backs). Monitor in practice; relax examples if real concerns are being dropped.

**R3: Model inconsistency at temperature 0.1.** Even at low temperature, gpt-5.2 produces slightly different output across runs. A good iteration-2 result doesn't guarantee the production run hits the same quality bar. Mitigation: the backfill generates fresh briefings for all relevant topics in one pass, so the production state matches a single generation batch. If a specific topic's headline comes out poorly, re-running the job for that topic is cheap.

**R4: Backfill cost creep.** ~$2–$4 is a rough estimate for ~20–40 topics. If the backfill scope is larger (e.g., all approved topics, not just last-30-days), cost and runtime grow linearly. Mitigation: scope backfill to the topics that actually appear on homepage and topic index (impact ≥ 2, last_activity_at ≥ 30 days ago). Topics outside that window get regenerated organically on their next trigger.

## Appendix A: New `instructions` text

This is the canonical new value for the `analyze_topic_briefing` PromptTemplate's `instructions` field. Paste verbatim into the admin UI and into `lib/prompt_template_data.rb`. Preserves `{{committee_context}}` and `{{context}}` placeholders so `PromptTemplate#interpolate` continues to work unchanged. This is the iteration-2 version — Plan Task 1's pre-deploy validation against four structurally different topics (extraterritorial review, fee schedule, sandy bay highlands, wastewater utility planning) caught two additional failure modes (CIPP/pipe-lining jargon, umbrella topic framing) and added fixes to the `<voice>` translation list, the rule 6 banned closers, and two new BAD examples.

```
Analyze this topic's history across meetings. Return a JSON analysis.

<voice>
- Write like a sharp neighbor who reads the agendas, not a policy analyst.
- Be skeptical of process and decisions, not of people.
- Translate jargon: "general obligation promissory notes" -> "borrowing",
  "land disposition" -> "selling city land", "parameters" -> "limits",
  "revenue bond" -> "rate-backed loan", "enterprise fund" -> "utility fund",
  "TID" / "T.I.D." -> "TIF district" (always spell out),
  "saw-cut" / "saw-cutting" -> "shave down" or "grind down the raised edges",
  "conditional use permit" -> "zoning variance",
  "certified survey map" -> "lot subdivision",
  "CIPP" / "cured in place pipe" -> "pipe-lining" (sewer rehab technique).
- NEVER reference your own source limitations. Don't say "the record
  provided does not show" or "in the materials provided." If you don't
  know the outcome, just write the quieter honest version.
- Keep it short. These readers scan, they don't study.
- Note who is affected by decisions and how. You can infer this from
  context, knowledgebase, public comment, and patterns over time — it
  won't be stated explicitly in city documents.
- Do not ascribe malice or bad intent to individuals.
</voice>

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
- The audience voice rules in <headline_criteria> below apply ONLY to three fields:
  `headline`, `upcoming_headline`, and `editorial_analysis.current_state`.
  All other fields (`factual_record`, `civic_sentiment`, `pattern_observations`,
  `process_concerns`, `continuity_signals`, `resident_impact`, `ambiguities`,
  `verification_notes`) must remain neutral, evidence-bound, and observational.
  Do not let the audience voice bleed into those fields.
</constraints>

{{committee_context}}

TOPIC CONTEXT (JSON):
{{context}}

<voice_scope>
The following three fields are the ONLY place the audience voice applies:
- `headline`
- `upcoming_headline`
- `editorial_analysis.current_state`

Every other field in the schema is neutral and observational. In particular:
- `factual_record` is dry, chronological reporting. No framing, no editorial voice.
- `civic_sentiment` is observational only — what residents said or did, not interpretive.
- `editorial_analysis.pattern_observations` is evidence-bound pattern noting; empty array is the default.
- `editorial_analysis.process_concerns` is null by default. ONLY populate it if the source data explicitly establishes a specific, concrete process issue. DO NOT retrofit a process_concern to justify a more interesting headline — the headline and the process_concerns field must be independently supported by the data.
- `continuity_signals` are evidence-bound signals only.
- `resident_impact.rationale` is a plain one-sentence explanation; no dramatization.
</voice_scope>

<headline_criteria>
The `headline`, `upcoming_headline`, and `editorial_analysis.current_state` fields have specific rules:

1. LEAD WITH THE MOST SPECIFIC CONCRETE DETAIL in the analysis — a dollar amount, a street name, a named program, a vote count, a deadline, a neighborhood. Specificity is the reason a resident clicks.

2. 20 WORDS MAX for headlines. One or two short sentences. Mobile-scanner-friendly. (current_state may be up to 3 sentences.)

3. TRANSLATE ALL JARGON. "Borrowing" not "general obligation promissory notes". "State loan" not "revenue bond". "Rates" not "enterprise fund structure". "Zoning change" not "rezoning request for conditional use overlay".

4. NAME A STAKE A RESIDENT RECOGNIZES: cost, their street, their rates, their neighborhood's character, who benefits, what changes about the city.

4a. WHEN MULTIPLE CONCRETE DETAILS COMPETE FOR THE LEAD, PREFER RESIDENT-PROXIMATE OVER IMPLEMENTATION MECHANISM. A resident cares about the sidewalks they walk on, not the saw-cutting technique. They care about their water main, not the procurement process. They care about their tax bill, not the bonding instrument. Lead with the detail closest to a resident's daily experience:
   - their street, their walk, their yard, their water pressure
   - their cost, their rate bill, their property tax
   - their neighborhood's character
   - who benefits (especially when it's a named business or developer)
   Only lead with the mechanism (contractor name, technique, financing instrument) when the mechanism IS the story — for example, when 0% financing is the unusual detail, or when the contractor has a contested history.

5. INTERESTING-NESS COMES FROM SPECIFICITY, NOT FROM FRAMING. If the facts are interesting, the headline is interesting. If the facts are thin, write a quiet honest headline; do not manufacture drama to make it punchy.

6. BANNED CLOSERS. Never end or open a headline with any of these phrases (or close variants):
   - "No vote has been reported yet"
   - "Vote unclear"
   - "Still pending"
   - "Still no clear decision"
   - "Keeps coming back" / "keep coming back"
   - "Keeps coming up" / "keep coming up"
   - "Keeps circling"
   - "Keeps popping up"
   - "Keep showing up" / "keeps showing up"
   - "Contract execution concerns"
   - "Discussion expected"
   If there is no concrete update, use the space for a stronger noun instead. Do not fill space with meta-commentary about the agenda process. "Umbrella topic" framings that list multiple sub-items without a specific lead are banned — pick the single strongest specific fact.

7. NO MANUFACTURED PROCESS CONCERNS. A headline may not imply a process problem unless `editorial_analysis.process_concerns` is a non-null value that explicitly supports it. Specifically, the following second-beat phrases are FORBIDDEN unless `process_concerns` or `pattern_observations` directly establishes them:
   - "Picked before the vote"
   - "Hasn't been spelled out"
   - "Hasn't been released"
   - "Now a question"
   - "Nobody has said"
   - "Still not clear why"

8. NO ASSERTED CAUSALITY OR SEQUENCE unless `factual_record` or `editorial_analysis.current_state` explicitly establishes it. The connectors "so", "to fund", "in order to", "because", "after", "before" require direct textual support in the analysis. Otherwise present facts as separate clauses or pick the single strongest fact.

9. NO ADJECTIVES OF OUTRAGE: no "shocking", "controversial", "wasteful", "rushed", "sneaky", "rubber-stamped", "green-lit", "sold as", "pitched as".

10. NO QUOTED JARGON. If you are reaching for quotation marks around a phrase from the source, translate it instead.

Examples that meet these criteria:
GOOD: "A $40,000 pilot will grind down the worst sidewalk trip hazards around town."
GOOD: "Two Rivers wants a 0% state loan to rebuild the water plant's backup power."
GOOD: "City puts TIF money into upgrades at two Two Rivers motels."
GOOD: "Council picks $349,985 bid for a new Lincoln Ave water main."
GOOD: "Lead pipe replacements are moving into 2026 contracts across Two Rivers."
GOOD: "Court fees are going up to match the state default."

BAD: "City is moving toward a $40,000 pilot to grind down sidewalk trip hazards. Where it'll happen is still unclear."
(Reason: manufactured concern in second clause; "still unclear" is not in the analysis.)

BAD: "Lead service line work is moving into big 2026 contracts, but 'contract execution concerns' are now on the table."
(Reason: quoted jargon; banned closer; vague adjective "big".)

BAD: "Garbage and recycling changes keep coming back to committee agendas. Still no clear decision reported."
(Reason: banned closers; zero specificity.)

BAD: "City moved from 'TIF talk' to real actions: ending two districts early and funding two motel/hotel upgrades."
(Reason: quoted jargon; asserted causality — "ending districts" and "funding motels" are two separate facts the headline has no warrant to link with causal sequencing.)

BAD: "$40,000 SafeStep pilot would saw-cut minor sidewalk trip hazards instead of replacing slabs."
(Reason: press-release voice — leads with the contractor name and the technique (saw-cut) instead of the resident-proximate detail. A resident cares about the trip hazards on their walk, not the saw-cutting method. Better: "A $40,000 pilot to shave down the worst sidewalk trip hazards around town.")

BAD: "Council considers Resolution 26-052 authorizing WPPI Energy loan for utility infrastructure improvements."
(Reason: resolution numbers and vendor names are not resident-proximate. Better: "$496,676 at 0%: borrowing for water plant generator repairs and security upgrades.")

BAD: "Lot sales, lot pricing, and possible expansion keep coming up for Sandy Bay Highlands."
(Reason: umbrella topic framing with three vague nouns and no specific lead; "keep coming up" is a banned closer variant. Better: pick the single strongest specific fact — e.g., "City reviewing pricing on Sandy Bay Highlands lots with Weichert Cornerstone" or "Sandy Bay Highlands subdivision eyes expansion after Lot 24 sale" — whichever is best supported by the analysis.)

BAD: "City lines up $1.84 million state loan for sewer upgrades; CIPP work shows up for 2025 and 2026."
(Reason: CIPP is untranslated jargon — translate to "pipe-lining". Also: second clause dilutes the lead. Better: "Two Rivers weighs a $1.84 million state loan for sewer pipe-lining through 2026.")

For `upcoming_headline`: the scheduled meeting body and date should be included (e.g., "Council votes Apr 21"). Return null if no upcoming meetings exist in the context.

For `editorial_analysis.current_state`: 1-3 sentences, same voice rules apply. This is the opening paragraph of "The Story" on the topic page; it should read as a natural continuation of the headline, not a restatement. Lead with the most specific concrete detail, translate jargon, no manufactured concerns, no asserted causality.
</headline_criteria>

<extraction_spec>
Return a JSON object matching this schema:
{
  "headline": "See <headline_criteria>. 20 words max. Lead with the most specific concrete detail. No banned closers. No manufactured process concerns. No asserted causality without analytical support.",
  "upcoming_headline": "See <headline_criteria>. Forward-looking. Includes committee name and date. Null if no upcoming meetings.",
  "editorial_analysis": {
    "current_state": "1-3 sentences. Follows <headline_criteria> voice rules. Opening paragraph of 'The Story' on the topic page.",
    "pattern_observations": ["NEUTRAL. Evidence-bound pattern observations when the timeline supports them — repeated deferrals, topic disappearing without resolution, repeated bouncing between bodies. Empty array is normal and expected for most topics. NOT the place for audience voice."],
    "process_concerns": "NEUTRAL. A specific, concrete process issue if one exists (e.g., topic deferred 3+ times, public hearing requirement skipped, repeated send-backs between bodies without resolution). Null for most topics. DO NOT populate this field to justify a more interesting headline — it must be independently supported by the source data.",
    "what_to_watch": "NEUTRAL. One sentence about what's next, or null."
  },
  "factual_record": [
    {"event": "NEUTRAL. What happened — plain language, no framing, no editorial voice.", "date": "YYYY-MM-DD", "meeting": "City Council or committee name"}
  ],
  "civic_sentiment": [
    {"observation": "NEUTRAL. What residents said or did — observational only.", "evidence": "Source", "meeting": "meeting name"}
  ],
  "continuity_signals": [
    {"signal": "recurrence|deferral|disappearance|cross_body_progression", "details": "NEUTRAL. Evidence-bound.", "meeting": "meeting name"}
  ],
  "resident_impact": {"score": 1, "rationale": "NEUTRAL. One sentence — why residents should care."},
  "ambiguities": ["What's still unclear"],
  "verification_notes": ["What to check"]
}
</extraction_spec>
```
