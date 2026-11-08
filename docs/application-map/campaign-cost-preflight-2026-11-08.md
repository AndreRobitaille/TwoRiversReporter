# Campaign cost planning: November 8, 2026

Application revision: `2d9acb16`, based on PR #276. This advances the cost
preparation portion of #238. It does not authorize paid work or complete spending
admission, provider accuracy evaluation or the campaign/action/outcome loop.

## Contract and boundary

The [AI cost contract](../superpowers/specs/2026-11-07-council-accountability-design.md#ai-cost-contract)
requires reviewable costs before an owner chooses the pilot allowance, shared
source analysis and no additional calls for unchanged input. Existing budget
admission requires prepared request estimates; it does not produce them.

ADM-21 now displays a read-only planning estimate for the retained source version.
The operator can also run `bin/rails 'council_profiles:campaign_preflight[SOURCE_ID]'`.
Both use the actual prepared parameters or an existing stage's pinned parameters,
the two-attempt limit and its remaining attempts. Completed/reusable analysis
shows no additional call. Held work stays held. Neither entry point creates a
stage, authorization, receipt or queued job. The CLI emits metadata and a digest,
not article text. Existing admin access rules still apply.

## Pricing and token assumptions

Official [Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna),
[Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra) and
[Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol) pages were fetched
on November 8. Standard direct API uncached-input/output USD per million tokens
were respectively 0.20/1.20, 2/12 and 4/20. These are separate from the application's
older evaluation-only price table, which this slice does not alter.

Planning prices every input token at the 1.25x cache-write rate, without assuming
a cache hit. [OpenAI caching documentation](https://developers.openai.com/api/docs/guides/prompt-caching)
describes that rate as replacing ordinary input pricing rather than an additive
fee. The model pages' long-input uplift is applied to the entire estimate above
272,000 input tokens: 2x input and 1.5x output. Rates and upward rounding use
integer micro-USD. Unknown models and unrecognized request shapes get no quote.

This is deliberately an **offline planning estimate, not an exact token count or
a guaranteed invoice ceiling**. It allows one input token per UTF-8 content byte
plus 1,024 tokens of formatting headroom, and the actual maximum completion-token
parameter. The formatting allowance is an engineering assumption, not a provider
guarantee. The [token-counting documentation](https://developers.openai.com/api/docs/guides/token-counting)
describes exact counting for Responses input and warns that local text counting
omits request framing. The current campaign transport is Chat Completions; this
slice neither migrates it nor calls a token-count endpoint.

The quote explicitly assumes Standard direct API pricing; regional, Fast mode,
other providers, tools and media are not priced here. The implementation requires
a pricing recheck after November 21, ahead of the November 30 Sol promotional
period end on the fetched [pricing page](https://developers.openai.com/api/docs/pricing).
A stale table displays unavailable, never a zero-cost quote.
Saved analysis remains reusable independently of pricing expiration.

## Real-data acceptance

The read-only operator command ran on the actual retained HTR source in the
separate local civic acceptance database. A second check used all retained
article heading/paragraph text: 9,020 characters, containing all five candidates.
No source text or private local artifact was added to Git.

For the configured GPT-5.6 Terra request, retained excerpts produced a planning
allowance of 7,324 input and 8,000 maximum output tokens: $0.114310 per attempt.
All retained article text produced 12,416 input and 8,000 output: $0.127040 per
attempt, $0.254080 for both possible attempts together. These are one-source
amounts shared across candidates, not per-member charges or measured usage.
The previously accepted reference returned reusable/zero additional cost.

The real-data check forbade AI client construction and verified unchanged
source, extraction, vote, budget and receipt counts. All 628 cohort votes stayed
intact. No allowance was created, input-token count measured, or paid call made.

## Verification

Ruby 4.0.9 and isolated PostgreSQL databases, one test worker:

- Focused cost/intake/update-trigger/job/view-hygiene tests: 25 tests,
  291 assertions, no failures/errors/skips. They cover later reads, no writes or
  queues, logged-out denial, CLI output, UTF-8 input, cache writes, long-context
  uplift, attempt limits, held work, stale/unknown pricing and unsupported inputs.
- `CHROME_BIN=/usr/bin/chromium bin/rails test test/system/campaign_extraction_journeys_test.rb`:
  2 journeys, 55 assertions, no failures/errors/skips. The new journey navigates
  to the source on a phone, opens cost assumptions, refreshes and proves no stage
  or allowance was created. No horizontal overflow; screenshot inspected.
- `bin/rubocop --cache false`: 755 files, no offenses. `git diff --check` passes.

After a clean seven-test baseline, a process-only fault removed the cache-write
uplift. The UTF-8 price assertion failed with 98,078 instead of 98,598 micro-USD
(one test, three assertions, one intended failure, no errors). No product file
was mutated; the restored focused run passed. Browser/regression fixtures are
deterministic and separate from the real-source acceptance above. Email transport
is captured; provider construction is forbidden for the new read-only paths.

Actual tokenization/billing, account processing tier, owner-selected pilot/day
allowances and real-provider extraction accuracy remain unverified. This report
cannot be passed directly to budget admission as a verified request estimate.
No paid AI, production operation, merge, deployment or backfill occurred.
