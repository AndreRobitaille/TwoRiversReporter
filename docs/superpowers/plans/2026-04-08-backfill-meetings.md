# One-Time Meeting Backfill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backfill all meetings and documents from two-rivers.org since January 1, 2025, running the full AI pipeline (topics, votes, members, summaries, briefings) on everything.

**Architecture:** Two rake tasks in a new `backfill` namespace. `backfill:run` triggers `DiscoverMeetingsJob` with a wide lookback. `backfill:status` queries Meeting, MeetingDocument, MeetingSummary, and Solid Queue tables to show pipeline progress. No new jobs, models, or pipeline changes.

**Tech Stack:** Rails rake tasks, Solid Queue (for job monitoring), existing scraper/AI pipeline.

---

### Task 1: Create the `backfill:run` rake task

**Files:**
- Create: `lib/tasks/backfill.rake`
- Test: `test/tasks/backfill_rake_test.rb`

- [ ] **Step 1: Write the failing test for `backfill:run`**

Create `test/tasks/backfill_rake_test.rb`:

```ruby
require "test_helper"

class BackfillRunRakeTest < ActiveSupport::TestCase
  setup do
    Rake::Task["backfill:run"].reenable
  end

  test "backfill:run enqueues DiscoverMeetingsJob with since 2025-01-01" do
    assert_enqueued_with(job: Scrapers::DiscoverMeetingsJob) do
      Rake::Task["backfill:run"].invoke
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/tasks/backfill_rake_test.rb -v`
Expected: FAIL — task not found / not defined

- [ ] **Step 3: Write the `backfill:run` rake task**

Create `lib/tasks/backfill.rake`:

```ruby
namespace :backfill do
  desc "One-time backfill: discover all meetings since 2025-01-01 and run the full pipeline"
  task run: :environment do
    since = Date.new(2025, 1, 1)
    puts "Starting backfill: discovering meetings since #{since}..."
    puts "This will enqueue ParseMeetingPageJob for each meeting found."
    puts "The full pipeline (download → extract → topics → votes → members → summarize) runs automatically."
    puts ""

    Scrapers::DiscoverMeetingsJob.perform_later(since: since)

    puts "DiscoverMeetingsJob enqueued. Monitor progress with: bin/rails backfill:status"
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/tasks/backfill_rake_test.rb -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/tasks/backfill.rake test/tasks/backfill_rake_test.rb
git commit -m "feat: add backfill:run rake task for one-time meeting backfill (#22)"
```

---

### Task 2: Create the `backfill:status` rake task

**Files:**
- Modify: `lib/tasks/backfill.rake`
- Test: `test/tasks/backfill_status_rake_test.rb`

- [ ] **Step 1: Write the failing test for `backfill:status`**

Create `test/tasks/backfill_status_rake_test.rb`:

```ruby
require "test_helper"

class BackfillStatusRakeTest < ActiveSupport::TestCase
  setup do
    Rake::Task["backfill:status"].reenable
  end

  test "backfill:status runs without error and prints meeting counts" do
    # Create a meeting in the backfill window
    Meeting.create!(
      detail_page_url: "https://two-rivers.org/meetings/test-1",
      starts_at: Date.new(2025, 6, 15),
      body_name: "City Council"
    )

    output = capture_io { Rake::Task["backfill:status"].invoke }.first

    assert_match(/Meetings since 2025-01-01/, output)
    assert_match(/Total meetings/, output)
  end

  test "backfill:status shows zero counts when no meetings exist" do
    output = capture_io { Rake::Task["backfill:status"].invoke }.first

    assert_match(/Total meetings:\s+0/, output)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/tasks/backfill_status_rake_test.rb -v`
Expected: FAIL — task not defined

- [ ] **Step 3: Write the `backfill:status` rake task**

Add to `lib/tasks/backfill.rake` inside the `namespace :backfill` block:

```ruby
  desc "Show backfill pipeline progress"
  task status: :environment do
    since = Date.new(2025, 1, 1)
    meetings = Meeting.where("starts_at >= ?", since)

    total = meetings.count
    with_docs = meetings.joins(:meeting_documents).distinct.count
    with_minutes = meetings.joins(:meeting_documents).where(meeting_documents: { document_type: "minutes_pdf" }).distinct.count
    with_text = meetings.joins(:meeting_documents).where.not(meeting_documents: { extracted_text: nil }).distinct.count
    with_topics = meetings.joins(:topics).distinct.count
    with_summaries = meetings.joins(:meeting_summaries).distinct.count

    # Solid Queue job counts (pending/in-progress)
    pending_jobs = SolidQueue::Job.where(finished_at: nil).count
    failed_jobs = SolidQueue::FailedExecution.count

    puts ""
    puts "=== Backfill Pipeline Status ==="
    puts "Meetings since #{since}"
    puts "-" * 40
    puts "Total meetings:        #{total}"
    puts "With any documents:    #{with_docs}"
    puts "With minutes PDF:      #{with_minutes}"
    puts "With extracted text:   #{with_text}"
    puts "With topics:           #{with_topics}"
    puts "With summaries:        #{with_summaries}"
    puts "-" * 40
    puts "Pending jobs:          #{pending_jobs}"
    puts "Failed jobs:           #{failed_jobs}"
    puts ""

    if failed_jobs > 0
      puts "⚠  Failed jobs detected. Check with: bin/rails runner 'SolidQueue::FailedExecution.last(10).each { |f| puts \"#{f.job.class_name}: #{f.error.to_s.truncate(120)}\" }'"
    end

    if pending_jobs > 0
      # Show job type breakdown
      puts "Pending job breakdown:"
      SolidQueue::Job.where(finished_at: nil).group(:class_name).count.sort_by { |_, v| -v }.each do |class_name, count|
        puts "  #{class_name}: #{count}"
      end
    end

    puts ""
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/tasks/backfill_status_rake_test.rb -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/tasks/backfill.rake test/tasks/backfill_status_rake_test.rb
git commit -m "feat: add backfill:status rake task for pipeline monitoring (#22)"
```

---

### Task 3: Verify full pipeline and update documentation

**Files:**
- Modify: `CLAUDE.md` (add backfill commands to the Commands table)

- [ ] **Step 1: Run the full test suite to ensure nothing is broken**

Run: `bin/rails test`
Expected: All tests pass

- [ ] **Step 2: Run lint**

Run: `bin/rubocop`
Expected: No new offenses

- [ ] **Step 3: Add backfill commands to CLAUDE.md**

Add these rows to the Commands table in `CLAUDE.md`:

```markdown
| Backfill all meetings since 2025 | `bin/rails backfill:run` |
| Check backfill progress | `bin/rails backfill:status` |
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add backfill commands to CLAUDE.md (#22)"
```

---

## Usage

```bash
# Start the backfill (enqueues the discover job)
bin/rails backfill:run

# In another terminal, monitor progress
bin/rails backfill:status

# Make sure the job worker is running
bin/jobs

# Check for failures
bin/rails runner 'SolidQueue::FailedExecution.last(10).each { |f| puts "#{f.job.class_name}: #{f.error.to_s.truncate(120)}" }'
```

## What happens

1. `backfill:run` enqueues `DiscoverMeetingsJob(since: 2025-01-01)`
2. DiscoverMeetingsJob paginates through two-rivers.org, upserts ~200+ meetings, enqueues `ParseMeetingPageJob` for each
3. Each `ParseMeetingPageJob` finds documents on the detail page, enqueues `DownloadJob` for each
4. `DownloadJob` uses conditional GET (etag/SHA256) — skips unchanged files, downloads new/updated ones
5. For PDFs: `AnalyzePdfJob` extracts text, then for minutes: enqueues `ExtractTopicsJob`, `ExtractVotesJob`, `ExtractCommitteeMembersJob`, `SummarizeMeetingJob`
6. `SummarizeMeetingJob` regenerates meeting + topic summaries (uses `find_or_initialize_by` — overwrites existing)
7. Topic briefings generated downstream via `GenerateTopicBriefingJob`
