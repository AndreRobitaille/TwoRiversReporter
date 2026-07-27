require "test_helper"
require "securerandom"

class Admin::JobRunsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = User.create!(
      email_address: "jobrun-admin@example.com",
      admin: true
    )
    sign_in_as_admin(@admin)

    @meeting = Meeting.create!(
      body_name: "City Council",
      detail_page_url: "https://example.com/meeting-job-runs-test",
      starts_at: Time.zone.parse("2026-03-01 18:00:00")
    )
    @topic = Topic.create!(name: "Job Run Topic #{SecureRandom.hex(4)}", status: "approved")
  end

  test "index shows job run console" do
    get admin_job_runs_url
    assert_response :success
    assert_select ".job-type-grid"
    assert_select ".job-type-card-name", text: "Scrape City Website (discover + process)"
    assert_select ".job-type-card-name", text: "Meeting Image"
    assert_select ".job-type-card-name", text: "Topic Image"
    assert_match(/repair incomplete pipeline stages/i, response.body)
  end

  test "create enqueues meeting-scoped jobs" do
    assert_enqueued_with(job: ExtractTopicsJob, args: [ @meeting.id ]) do
      post admin_job_runs_url, params: {
        job_type: "extract_topics",
        date_from: "2026-03-01",
        date_to: "2026-03-31"
      }
    end
    assert_redirected_to admin_job_runs_url
    assert_match(/enqueued/i, flash[:notice])
  end

  test "create enqueues scraper job" do
    assert_enqueued_with(job: Scrapers::FullPipelineRefreshJob) do
      post admin_job_runs_url, params: {
        job_type: "discover_meetings"
      }
    end
    assert_redirected_to admin_job_runs_url
  end

  test "create enqueues meeting image job" do
    assert_enqueued_with(job: GeneratedImages::GenerateForMeetingJob, args: [ @meeting.id ]) do
      post admin_job_runs_url, params: {
        job_type: "generate_meeting_image",
        date_from: "2026-03-01",
        date_to: "2026-03-31"
      }
    end

    assert_redirected_to admin_job_runs_url
    assert_match(/Meeting Image/i, flash[:notice])
  end

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

  test "count returns target count for meeting-scoped jobs" do
    get count_admin_job_runs_url, params: {
      job_type: "extract_topics",
      date_from: "2026-03-01",
      date_to: "2026-03-31"
    }, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["count"]
  end

  # Both assertions are scoped to the element that actually carries the page
  # heading. A bare `assert_match "Run a Job", response.body` passes on every
  # admin page in the app: Admin::Navigation renders that exact string as a
  # sidebar link label in the layout, so the assertion was satisfied by the
  # chrome and would not have noticed the heading being renamed to anything
  # at all — proven by mutation (final review, M3).
  test "the enqueue console is titled for what it does" do
    get admin_job_runs_url
    assert_response :success
    assert_select ".section-header__label", text: "Run a Job"
    assert_no_match "Job Re-Run Console", response.body
  end

  test "the queue monitor is titled for what it does" do
    get admin_jobs_url
    assert_response :success
    assert_select ".adm-page-header__title", text: "Queue & Failures"
  end
end
