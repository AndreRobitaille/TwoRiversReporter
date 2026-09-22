# OpenAI Model Evaluation

Two Rivers Reporter treats model upgrades as product-quality evaluations, not
constant replacements. Production prompt history is the preferred corpus because
`PromptRun.messages` preserves the exact effective prompt sent at the time.

## Current routing

| Tier | Model | Intended use |
| --- | --- | --- |
| `heavy` | `gpt-5.6-sol` | Available for a workload that demonstrates a repeatable quality gain; currently unused |
| `default` | `gpt-5.6-terra` | Civic analysis, extraction, synthesis, and knowledge work |
| `lightweight` | `gpt-5.6-luna` | Mechanical extraction, descriptions, interim copy, and image briefs |

All GPT-5.6 production calls explicitly use `reasoning_effort: none`. A limited
`low` comparison increased latency and cost without a consistent quality gain.
Model names remain environment-configurable through `OPENAI_HEAVY_MODEL`,
`OPENAI_REASONING_MODEL`, and `OPENAI_LIGHTWEIGHT_MODEL`.

## Running an evaluation

The admin prompt editor can test unsaved prompt text against a historical run.
Choose an evaluation model and `none` or `low` reasoning on the Examples tab.
Experimental calls show duration, JSON validity, token usage, cached and reasoning
tokens, and an approximate dated cost. They never create `PromptRun` rows.

For a repeatable developer-side batch:

```sh
RUN_IDS=15178,15171 \
MODELS=gpt-5.6-terra,gpt-5.6-sol \
REASONING_EFFORT=none \
PROMPT_SOURCE=historical \
OUTPUT=tmp/prompt_evals/baseline.json \
bin/rails prompt_evals:run
```

Use `PROMPT_SOURCE=historical` to replay the saved messages exactly. Use
`PROMPT_SOURCE=repository` to interpolate the repository prompt with the run's
stored placeholders without changing the database. Output is local JSON under
`tmp/` unless `OUTPUT` is set. The task reads historical rows but does not write
application data.

Review structured tasks for schema, factual correctness, completeness,
classification, entity handling, and invented facts. Review editorial tasks for
grounding, chronology, resident relevance, calibrated intensity, legal and
financial precision, evidence/inference separation, and information loss. Valid
JSON and attractive prose are necessary but not sufficient.

## August 2026 GPT-5.6 decision

The initial corpus used 18 recent historical runs:

- Three meeting analyses: City Council, BIDC/CDA, and an agenda-only
  Environmental Advisory Board preview.
- Three topic extractions: a dense City Council agenda, a development-body
  meeting, and routine absentee-ballot processing.
- Three topic briefings, including housing, a split grant-application vote, and
  a split beach-parking decision.
- Two topic summaries about a proposed property acquisition and housing concept.
- Three detailed descriptions, two committee-member extractions, and two image
  briefs.

The unchanged-prompt baseline made 36 GPT-5.6 calls with no API errors or JSON
parse failures. Terra was faster and substantially cheaper than Sol. Sol sometimes
returned more timeline or meeting-detail entries, but the advantage was not stable
after prompt cleanup and it over-classified routine/cross-topic material in one
topic-extraction case. Terra therefore remains the analytical default. Luna matched
or improved the mechanical examples at about one-tenth Terra's cost; an explicit
string schema fixed its only observed image-brief shape error.

An aggressive briefing rewrite reduced instruction text by about 75% but collapsed
chronology, so it was rejected. The retained briefing cleanup is conservative: it
consolidates duplicated voice scope and replaces unsafe jargon substitutions with
a precision rule. The topic-summary impact rubric was reduced about 31% while
retaining scores and evidence boundaries on the evaluated cases.

## Safe prompt rollout

Do not run `prompt_templates:populate` casually in production; it overwrites all
editable prompt rows from repository data. Plan selected changes first:

```sh
KEYS=analyze_topic_briefing,analyze_topic_summary,generated_image_brief \
bin/rails prompt_templates:sync_selected
```

The dry run prints current and target SHA-256 fingerprints. To apply, supply the
observed current fingerprint for every existing row:

```sh
KEYS=analyze_topic_briefing,analyze_topic_summary,generated_image_brief \
EXPECTED_SHA256S=analyze_topic_briefing=...,analyze_topic_summary=...,generated_image_brief=... \
APPLY=true \
bin/rails prompt_templates:sync_selected
```

The task aborts on any mismatch and uses normal model callbacks so the prior text
is retained in `PromptVersion` history.

## Follow-up

Keep Chat Completions for this model/prompt baseline. Evaluate a Responses API
migration separately, along with strict JSON Schema structured outputs, so endpoint
and schema changes are not confounded with this model decision.

Official references:

- [GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
- [GPT-5.6 Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra)
- [GPT-5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna)
- [Latest-model migration guidance](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-5.6)
