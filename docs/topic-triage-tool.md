# Topic Triage Tool

This tool is a temporary automation aid for cleaning up topic noise and
over-fragmentation. It uses an LLM to suggest merges, approvals, and
procedural blocks, then optionally applies them.

## What it does
- Scans proposed topics only (`status: proposed`).
- Suggests merges into canonical, resident-facing topics.
- Approves clear, substantive topics.
- Blocks procedural/admin noise (minutes, roll call, agenda headers).
- Logs actions and suggestions to `log/topic_triage.log`.

## Entry point
Service: `Topics::TriageTool`

Default behavior:
- Review-only (no changes) unless `apply: true` and `dry_run: false`.
- Uses OpenAI by default; Gemini is opt-in.

## Automatic triage after scraper runs

`Topics::AutoTriageJob` runs automatically after topic extraction. Each
`ExtractTopicsJob` enqueues it with a 3-minute delay so extraction jobs
from the same scraper run complete first. The job is idempotent — multiple
enqueues are safe.

Auto-triage uses `min_confidence: 0.9` and applies changes directly.
Topics below the confidence threshold remain in the review queue for
manual review.

## Manual run commands
Dry run (no changes):
```
bin/rails runner "Topics::TriageTool.call"
```

Apply changes (recommended confidence threshold):
```
bin/rails runner "Topics::TriageTool.call(apply: true, dry_run: false, min_confidence: 0.9, max_topics: 50)"
```

Smaller batch size:
```
bin/rails runner "Topics::TriageTool.call(apply: true, dry_run: false, min_confidence: 0.9, max_topics: 25)"
```

## AI provider configuration
OpenAI (default):
- Uses `OPENAI_REASONING_MODEL` (defaults to `gpt-5.2`).
- Uses `openai_access_token` (Rails credentials) or `OPENAI_ACCESS_TOKEN`.

Gemini (opt-in):
- Set `USE_GEMINI=true` and provide `gemini_access_token` in credentials or
  `GEMINI_ACCESS_TOKEN`.
- Model can be overridden via `GEMINI_MODEL` (defaults to
  `gemini-3-pro-preview`).

## Logging & audit
- All runs write to `log/topic_triage.log` with UTC timestamps.
- If a user is available (via `user_id` or `user_email`), the tool records
  `TopicReviewEvent` entries for approvals/blocks/merges.
- If no user is provided, it only logs to the file.

## Guardrails
- Only applies actions with confidence >= `min_confidence`.
- Skips merges when canonical topic is missing or invalid.
- Leaves ambiguous items untouched.

## Notes
- Auto-triage handles the high-confidence bulk work (procedural blocks,
  obvious merges, clear approvals). The admin review queue is for
  everything the AI is uncertain about.
- Manual runs are still useful for one-off cleanup or adjusting the
  confidence threshold.
