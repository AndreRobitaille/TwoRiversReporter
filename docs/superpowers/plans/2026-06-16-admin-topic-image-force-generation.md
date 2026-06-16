# Admin Topic Image Force Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make explicit admin-triggered topic image generation actually attempt image generation instead of silently returning when automatic image generation is disabled.

**Architecture:** Keep `GENERATED_IMAGES_ENABLED` as protection for automatic/background image generation. Treat forced topic image jobs as explicit editorial overrides that may run even when automatic image generation is disabled; the admin job console enqueues `GeneratedImages::GenerateForTopicJob` with `force: true`, matching the existing topic-page regenerate action. Do not change public display logic.

**Tech Stack:** Rails 8, ActiveJob, Minitest integration tests.

---

## File Structure

- Modify `app/controllers/admin/job_runs_controller.rb`: in `enqueue_jobs`, pass `force: true` only for `GeneratedImages::GenerateForTopicJob` topic jobs from the admin job console.
- Modify `app/jobs/generated_images/generate_for_topic_job.rb`: allow `force: true` and custom prompt runs to bypass the global automatic-generation flag.
- Modify `test/controllers/admin/job_runs_controller_test.rb`: update the existing topic image enqueue assertion to expect the force option.
- Modify `test/jobs/generated_images/generate_for_topic_job_test.rb`: add coverage proving forced topic image generation runs even when global automatic generation is disabled.

## Task 1: Admin Job Console Enqueues Forced Topic Image Jobs

**Files:**
- Modify: `test/controllers/admin/job_runs_controller_test.rb:76-86`
- Modify: `app/controllers/admin/job_runs_controller.rb:67-83`

- [ ] **Step 1: Write the failing test**

Change the existing test in `test/controllers/admin/job_runs_controller_test.rb` to expect `force: true`:

```ruby
  test "create enqueues topic image job" do
    assert_enqueued_with(job: GeneratedImages::GenerateForTopicJob, args: [ @topic.id, { force: true } ]) do
      post admin_job_runs_url, params: {
        job_type: "generate_topic_image",
        topic_ids: [ @topic.id ]
      }
    end

    assert_redirected_to admin_job_runs_url
    assert_match(/Topic Image/i, flash[:notice])
  end
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
bin/rails test test/controllers/admin/job_runs_controller_test.rb:76
```

Expected: failure because the controller currently enqueues `GeneratedImages::GenerateForTopicJob` with only `[ @topic.id ]`.

- [ ] **Step 3: Implement the minimal controller change**

Replace the topic branch in `app/controllers/admin/job_runs_controller.rb` with this implementation:

```ruby
    when :topic
      if config[:job] == Topics::GenerateTopicBriefingJob
        targets.each do |topic|
          latest_meeting_id = Meeting.where(id: topic.agenda_items.select(:meeting_id)).order(starts_at: :desc).pick(:id)
          config[:job].perform_later(topic_id: topic.id, meeting_id: latest_meeting_id) if latest_meeting_id
        end
      elsif config[:job] == GeneratedImages::GenerateForTopicJob
        targets.each { |topic| config[:job].perform_later(topic.id, force: true) }
      else
        targets.each { |topic| config[:job].perform_later(topic.id) }
      end
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run:

```bash
bin/rails test test/controllers/admin/job_runs_controller_test.rb:76
```

Expected: pass.

- [ ] **Step 5: Run the full controller test file**

Run:

```bash
bin/rails test test/controllers/admin/job_runs_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 6: Run the topic image job test file**

Run:

```bash
bin/rails test test/jobs/generated_images/generate_for_topic_job_test.rb
```

Expected: all tests pass, confirming existing forced-job behavior remains intact.

## Self-Review

- Spec coverage: The plan implements the approved option: explicit admin topic image jobs force generation while automatic image jobs still obey existing job behavior.
- Placeholder scan: No placeholders remain.
- Type consistency: Uses existing `GeneratedImages::GenerateForTopicJob.perform_later(topic.id, force: true)` signature already covered by topic-page regenerate tests.
