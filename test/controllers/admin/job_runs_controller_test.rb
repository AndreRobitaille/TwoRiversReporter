require "test_helper"

class Admin::JobRunsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = User.create!(
      email_address: "jobrun-admin@example.com",
      password: "password123456",
      admin: true,
      totp_enabled: true
    )
    @admin.ensure_totp_secret!

    post session_url, params: {
      email_address: @admin.email_address,
      password: "password123456"
    }
    post mfa_session_url, params: {
      code: ROTP::TOTP.new(@admin.totp_secret).now
    }

    @meeting = Meeting.create!(
      body_name: "City Council",
      detail_page_url: "https://example.com/meeting-job-runs-test",
      starts_at: Time.zone.parse("2026-03-01 18:00:00")
    )
  end

  test "index shows job run console" do
    get admin_job_runs_url
    assert_response :success
    assert_select ".job-type-grid"
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
    assert_enqueued_with(job: Scrapers::DiscoverMeetingsJob) do
      post admin_job_runs_url, params: {
        job_type: "discover_meetings"
      }
    end
    assert_redirected_to admin_job_runs_url
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
end
