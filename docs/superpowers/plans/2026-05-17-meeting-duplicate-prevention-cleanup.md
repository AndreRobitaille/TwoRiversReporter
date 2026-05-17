# Meeting Duplicate Prevention and Future Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop new duplicate meeting records caused by changing city detail URLs and safely clean obvious duplicates in the meetings page window.

**Architecture:** Keep the current `/meetings` display dedupe as a public-facing safety net. Add source-level duplicate matching in `Scrapers::DiscoverMeetingsJob` using `starts_at` plus normalized meeting name before falling back to `detail_page_url`. Add a narrow service and rake task that cleans only high-confidence duplicate groups in the same time window as `/meetings`.

**Tech Stack:** Rails, ActiveJob, ActiveRecord, Minitest, Rake.

---

### Task 1: Source-level duplicate prevention in discovery

**Files:**
- Modify: `app/jobs/scrapers/discover_meetings_job.rb`
- Test: `test/jobs/scrapers/discover_meetings_committee_test.rb`

- [ ] **Step 1: Write the failing test**

Add a test that builds a fake meeting row with a new detail URL but the same future date and normalized body name as an existing meeting. Assert discovery reuses the existing meeting and updates its URL instead of creating a second row.

- [ ] **Step 2: Run the test to verify RED**

Run: `bin/rails test test/jobs/scrapers/discover_meetings_committee_test.rb`

Expected: the new test fails because `process_row` currently matches only `detail_page_url`.

- [ ] **Step 3: Implement minimal prevention**

In `Scrapers::DiscoverMeetingsJob`, extract normalized body name logic and select an existing meeting by exact `starts_at` plus normalized body name before `Meeting.find_or_initialize_by(detail_page_url: detail_url)` creates a new record.

- [ ] **Step 4: Run test to verify GREEN**

Run: `bin/rails test test/jobs/scrapers/discover_meetings_committee_test.rb`

Expected: all tests pass.

### Task 2: Meetings-window duplicate cleanup service

**Files:**
- Create: `app/services/meetings/window_duplicate_cleanup.rb`
- Test: `test/services/meetings/window_duplicate_cleanup_test.rb`

- [ ] **Step 1: Write failing tests**

Cover these behaviors: a future duplicate group keeps the meeting with documents and deletes an empty duplicate; a past duplicate inside the `/meetings` window keeps the useful record and deletes the empty one; dry-run reports deletion candidates without changing rows; duplicates outside the `/meetings` window are ignored; all-empty duplicates keep a single cancelled record when present; ambiguous groups with multiple useful records are skipped.

- [ ] **Step 2: Run tests to verify RED**

Run: `bin/rails test test/services/meetings/window_duplicate_cleanup_test.rb`

Expected: fails because the service does not exist.

- [ ] **Step 3: Implement minimal service**

Create `Meetings::WindowDuplicateCleanup` with `call(dry_run: true)` returning a report hash. Group meetings in the `/meetings` window by exact `starts_at` plus normalized body name. Clean only when exactly one record has useful associated data and the losers are empty, or when all records are empty and exactly one record is cancelled. Skip groups with multiple useful records.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `bin/rails test test/services/meetings/window_duplicate_cleanup_test.rb`

Expected: all tests pass.

### Task 3: Rake task entrypoint

**Files:**
- Create: `lib/tasks/meetings.rake`
- Test: covered through service tests; rake task is a thin wrapper.

- [ ] **Step 1: Add dry-run-first task**

Create `meetings:cleanup_window_duplicates` with `DRY_RUN=true` default. It calls `Meetings::WindowDuplicateCleanup.call(dry_run: dry_run)` and prints report lines.

- [ ] **Step 2: Manually verify task loads**

Run: `bin/rails -T meetings`

Expected: task appears.

- [ ] **Step 3: Run dry-run locally**

Run: `bin/rails meetings:cleanup_window_duplicates`

Expected: prints a report and does not delete rows.

### Task 4: Final verification

**Files:**
- Modified files from Tasks 1-3.

- [ ] **Step 1: Run targeted tests**

Run: `bin/rails test test/jobs/scrapers/discover_meetings_committee_test.rb test/services/meetings/window_duplicate_cleanup_test.rb test/controllers/meetings_controller_test.rb`

Expected: 0 failures, 0 errors.

- [ ] **Step 2: Run lint on changed Ruby files**

Run: `bin/rubocop app/controllers/meetings_controller.rb app/models/meeting.rb app/jobs/scrapers/discover_meetings_job.rb app/services/meetings/window_duplicate_cleanup.rb test/controllers/meetings_controller_test.rb test/jobs/scrapers/discover_meetings_committee_test.rb test/services/meetings/window_duplicate_cleanup_test.rb lib/tasks/meetings.rake`

Expected: no offenses.

- [ ] **Step 3: Review diff**

Run: `git diff -- app/controllers/meetings_controller.rb app/models/meeting.rb app/jobs/scrapers/discover_meetings_job.rb app/services/meetings/window_duplicate_cleanup.rb test/controllers/meetings_controller_test.rb test/jobs/scrapers/discover_meetings_committee_test.rb test/services/meetings/window_duplicate_cleanup_test.rb lib/tasks/meetings.rake docs/superpowers/plans/2026-05-17-meeting-duplicate-prevention-cleanup.md`

Expected: only duplicate prevention, future cleanup, tests, and this plan changed.
