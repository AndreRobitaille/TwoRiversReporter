# Background job recovery verification

Scope: BG-02 agenda reconciliation, BG-04 topic triage, and generated-image failure handling. Acceptance follows the safe mixed-mode agenda rerun design, Topic Governance, and generated civic image failure/cost controls.

- A reference added to or removed from an otherwise identical child title updates the existing agenda item. Different reference numbers and substantive title changes still fail closed. An HTML-source replay checks the retained item/parent IDs, topic, appearance, motion, linked document, revised summary and a later no-op rerun.
- Triage requests a strict response schema and validates the entire result before applying any action. Duplicate keys remain errors. At most two provider responses are attempted per run. A malformed result followed by a valid three-topic plan preserves all three distinct approvals, audit events and downstream description jobs; repeated malformed output applies nothing.
- Global automatic triage uses Solid Queue serialization, with waiting work retained. A real local queue test claims and completes one run, then verifies release of the waiting run. Identical successfully processed context is skipped for one hour; changed context and expired cache run again, and failures are never cached as completed. Manual triage remains uncached.
- Image HTTP errors retain the provider message, code and request ID, without dumping headers or request content. API-key strings are redacted. Permanent client rejections escape the generic network retry handler; timeouts, throttling and server errors retain retry handling. The job-boundary test checks a persisted failed image and zero queued retries. No image model or visual content policy changes.

The response format follows [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=chat). Provider transport is simulated in local tests; the real jobs, services, parsing, database writes and queue transitions execute.

## Defect detection

Five separate test processes injected bounded runtime faults, leaving application files unchanged. Each produced an intended assertion failure, not a boot/syntax failure:

1. Permissive duplicate-key parsing lost three approvals (expected three downstream jobs, got zero).
2. Treating different reference numbers as equivalent bypassed the expected ambiguity exception.
3. Classifying HTTP 400 as transient enqueued a retry (expected zero, got one).
4. Disabling completed-input reuse produced two provider calls instead of one.
5. Allowing two simultaneous global triages left the second ready instead of blocked.

Targeted baseline: 92 tests, 376 assertions, no failures/errors/skips. Broader restored checks and release results are recorded below when complete.

Restored full application suite: `bin/rails test` ran 2,109 tests / 12,573 assertions, zero failures/errors and one existing skip. `bin/rubocop` inspected 611 files clean. `bin/bundler-audit`, `bin/importmap audit`, and Brakeman passed with no vulnerabilities/warnings (temporary writable cache paths used for sandbox compatibility).

Browser suite: `PARALLEL_WORKERS=1 bin/rails test:system` with Chromium and writable temporary XDG paths ran 17 tests / 655 assertions, zero failures/errors/skips. It ran after application tests against the same local test database. These existing browser journeys cover site/navigation/access regressions; the new job behavior is verified by the deterministic pipeline and actual local Solid Queue tests above.
