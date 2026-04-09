require "test_helper"
require "minitest/mock"

class Scrapers::DiscoverTranscriptsJobTest < ActiveJob::TestCase
  setup do
    @council_meeting = Meeting.create!(
      body_name: "City Council Meeting",
      detail_page_url: "http://example.com/council-apr-6",
      starts_at: 1.day.ago
    )
    @work_session = Meeting.create!(
      body_name: "City Council Work Session",
      detail_page_url: "http://example.com/ws-mar-30",
      starts_at: 47.hours.ago
    )
    @plan_commission = Meeting.create!(
      body_name: "Plan Commission",
      detail_page_url: "http://example.com/plan-commission",
      starts_at: 1.day.ago
    )
    @old_meeting = Meeting.create!(
      body_name: "City Council Meeting",
      detail_page_url: "http://example.com/council-old",
      starts_at: 5.days.ago
    )
  end

  def stub_status(success_bool)
    status = Minitest::Mock.new
    status.expect :success?, success_bool
    status
  end

  test "parses standard council meeting title and enqueues download" do
    date_str = @council_meeting.starts_at.strftime("%B %-d, %Y")
    yt_output = "abc123 | City Council Meeting for Thursday, #{date_str}\n"

    Open3.stub :capture3, [ yt_output, "", stub_status(true) ] do
      assert_enqueued_with(job: Documents::DownloadTranscriptJob, args: [ @council_meeting.id, "https://www.youtube.com/watch?v=abc123" ]) do
        Scrapers::DiscoverTranscriptsJob.perform_now
      end
    end
  end

  test "parses work session title and enqueues download" do
    date_str = @work_session.starts_at.strftime("%B %-d, %Y")
    yt_output = "def456 | City Council Work Session for Monday, #{date_str}\n"

    Open3.stub :capture3, [ yt_output, "", stub_status(true) ] do
      assert_enqueued_with(job: Documents::DownloadTranscriptJob, args: [ @work_session.id, "https://www.youtube.com/watch?v=def456" ]) do
        Scrapers::DiscoverTranscriptsJob.perform_now
      end
    end
  end

  test "skips videos that cannot be parsed" do
    yt_output = "xyz999 | Some Random Live Stream\n"

    Open3.stub :capture3, [ yt_output, "", stub_status(true) ] do
      assert_no_enqueued_jobs only: Documents::DownloadTranscriptJob do
        Scrapers::DiscoverTranscriptsJob.perform_now
      end
    end
  end

  test "skips meetings that already have a transcript" do
    MeetingDocument.create!(
      meeting: @council_meeting,
      document_type: "transcript",
      source_url: "https://www.youtube.com/watch?v=existing"
    )

    date_str = @council_meeting.starts_at.strftime("%B %-d, %Y")
    yt_output = "abc123 | City Council Meeting for Thursday, #{date_str}\n"

    Open3.stub :capture3, [ yt_output, "", stub_status(true) ] do
      assert_no_enqueued_jobs only: Documents::DownloadTranscriptJob do
        Scrapers::DiscoverTranscriptsJob.perform_now
      end
    end
  end

  test "skips non-council meetings even if title matches date" do
    date_str = @plan_commission.starts_at.strftime("%B %-d, %Y")
    # Plan Commission title won't match TITLE_PATTERN — no job enqueued
    yt_output = "ghi789 | Plan Commission Meeting for Tuesday, #{date_str}\n"

    Open3.stub :capture3, [ yt_output, "", stub_status(true) ] do
      assert_no_enqueued_jobs only: Documents::DownloadTranscriptJob do
        Scrapers::DiscoverTranscriptsJob.perform_now
      end
    end
  end

  test "handles yt-dlp failure gracefully" do
    Open3.stub :capture3, [ "", "yt-dlp: command not found", stub_status(false) ] do
      assert_no_enqueued_jobs only: Documents::DownloadTranscriptJob do
        assert_nothing_raised do
          Scrapers::DiscoverTranscriptsJob.perform_now
        end
      end
    end
  end
end
