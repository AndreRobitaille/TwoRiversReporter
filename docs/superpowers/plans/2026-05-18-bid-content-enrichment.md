# BID Content Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve BID boundary-expansion research and enrich Topic 73 / Meeting 190 with documented, non-speculative context.

**Architecture:** This is a content-only update. Durable research and Facebook-post questions live in `tmp/bid/bid-boundary-context-and-facebook-questions.txt`; live page copy is updated through existing database fields for Topic 73 and Meeting 190, without changing controllers, views, jobs, or prompts.

**Tech Stack:** Rails runner, existing `TopicBriefing` / `MeetingSummary` records, local text artifact in `tmp/bid`.

---

### Task 1: Preserve BID research in tmp

**Files:**
- Create: `tmp/bid/bid-boundary-context-and-facebook-questions.txt`

- [ ] **Step 1: Create the research note**

Write a text note that includes:

- verified document timeline from 2020, 2022, 2024, 2025, and the May 21, 2026 agenda;
- BID rate/levy/cap figures;
- Main Street budget overhead figures;
- current-map caveat;
- safe framing notes that avoid assigning motive;
- Facebook-post questions for later use.

- [ ] **Step 2: Verify the note exists**

Run: `test -s tmp/bid/bid-boundary-context-and-facebook-questions.txt`

Expected: command exits successfully.

### Task 2: Update live content via existing records

**Files:**
- Modify data only: `Topic.find(73).topic_briefing`
- Modify data only: `Meeting.find(190).meeting_summaries.order(created_at: :desc).first`

- [ ] **Step 1: Back up current records to tmp**

Use Rails runner to export current Topic 73 briefing and Meeting 190 summary into `tmp/bid/bid-content-backup-before-enrichment.json`.

- [ ] **Step 2: Update Topic 73 briefing**

Revise headline, editorial content, factual record, ambiguities, and what-to-watch language. Keep all claims tied to documents. Frame the core issue as whether boundary expansion preserves the current Main Street operating model without yet documenting parcel-level special benefit.

- [ ] **Step 3: Update Meeting 190 preview**

Revise meeting summary generation data so the meeting preview highlights missing specifics: no proposed map or parcel list in the agenda, boundary recommendation may go to Plan Commission/Council, and attendees should watch for revenue/service-benefit justifications.

### Task 3: Verify content-only update

**Files:**
- Read data only: Topic 73, Meeting 190

- [ ] **Step 1: Query updated records**

Run a Rails runner query that prints Topic 73 headline/editorial/record and Meeting 190 headline/item summaries.

Expected: output includes the new budget, cap, overhead, and special-benefit context.

- [ ] **Step 2: Ensure no code files changed unexpectedly**

Run: `git status --short`

Expected: only the plan and tmp note/backups should appear as file changes; database changes may not appear in git.

Do not commit unless explicitly requested.
