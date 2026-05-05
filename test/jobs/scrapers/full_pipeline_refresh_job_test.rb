require "test_helper"

class Scrapers::FullPipelineRefreshJobTest < ActiveJob::TestCase
  test "full pipeline job invokes discover helper and repair sweep" do
    meetings = [
      Meeting.create!(detail_page_url: "https://example.com/full-refresh-1", starts_at: 1.day.ago),
      Meeting.create!(detail_page_url: "https://example.com/full-refresh-2", starts_at: 2.days.ago)
    ]
    sweep = Minitest::Mock.new
    sweep.expect :call, { meetings_scoped: 2, parse_meeting_pages_enqueued: 0, document_downloads_enqueued: 0, agenda_parses_enqueued: 0, summaries_enqueued: 0 }

    parsed_ids = []

    Scrapers::DiscoverMeetingsJob.stub :run_inline!, ->(**_) { Scrapers::DiscoverTranscriptsJob.perform_later; meetings.map(&:id) } do
      Scrapers::ParseMeetingPageJob.stub :perform_now, ->(id, enqueue_downloads: true) {
        parsed_ids << id
        Meeting.find(id).mark_processing!(:meeting_page_parsed_at)
      } do
        Scrapers::PipelineRepairSweep.stub :new, ->(discovered_ids, parsed_meeting_ids: nil, since: nil) {
          assert_equal meetings.map(&:id), discovered_ids
          assert_equal meetings.map(&:id), parsed_meeting_ids
          assert_nil since
          sweep
        } do
          assert_enqueued_with(job: Scrapers::DiscoverTranscriptsJob) do
            assert_equal({ meetings_scoped: 2, parse_meeting_pages_enqueued: 0, document_downloads_enqueued: 0, agenda_parses_enqueued: 0, summaries_enqueued: 0 }, Scrapers::FullPipelineRefreshJob.perform_now)
          end
        end
      end
    end

    assert_equal meetings.map(&:id), parsed_ids
    sweep.verify
  end

  test "full refresh avoids duplicate parse jobs for newly discovered meetings" do
    meeting = Meeting.create!(detail_page_url: "https://www.two-rivers.org/meetings/duplicate", starts_at: 1.day.ago)

    Scrapers::DiscoverMeetingsJob.stub :run_inline!, [ meeting.id ] do
      assert_no_enqueued_jobs only: Scrapers::ParseMeetingPageJob do
        Scrapers::FullPipelineRefreshJob.perform_now
      end
    end
  end

  test "full refresh parses newly discovered meetings inline" do
    meeting = Meeting.create!(detail_page_url: "https://www.two-rivers.org/meetings/new", starts_at: 1.day.ago)

    parsed_ids = []

    Scrapers::DiscoverMeetingsJob.stub :run_inline!, [ meeting.id ] do
      Scrapers::ParseMeetingPageJob.stub :perform_now, ->(id, enqueue_downloads: true) { parsed_ids << id } do
        Scrapers::FullPipelineRefreshJob.perform_now
      end
    end

    assert_equal [ meeting.id ], parsed_ids
  end

  test "discover meetings helper returns ids while still enqueuing parse jobs" do
    date_span = Object.new
    date_span.define_singleton_method(:[]) { |_key| (Time.current + 1.day).to_s }

    details_link = Object.new
    details_link.define_singleton_method(:[]) { |_key| "/meetings/1" }

    title = Object.new
    title.define_singleton_method(:text) { "City Council Meeting" }

    row = Object.new
    row.define_singleton_method(:at) do |selector|
      case selector
      when ".views-field-field-calendar-date span" then date_span
      when ".views-field-title" then title
      when ".views-field-view-node a" then details_link
      end
    end

    page = Object.new
    page.define_singleton_method(:search) do |selector|
      raise "unexpected selector" unless selector == "table.views-table tbody tr"
      [ row ]
    end
    page.define_singleton_method(:link_with) { |_args| nil }

    agent = Minitest::Mock.new
    agent.expect :user_agent_alias=, "Mac Safari", [ "Mac Safari" ]
    agent.expect :get, page, [ Scrapers::DiscoverMeetingsJob::MEETINGS_URL ]

    Mechanize.stub :new, agent do
      assert_enqueued_with(job: Scrapers::ParseMeetingPageJob) do
        ids = Scrapers::DiscoverMeetingsJob.run_inline!(since: 1.day.ago)
        assert_equal [ Meeting.find_by!(detail_page_url: "https://www.two-rivers.org/meetings/1").id ], ids
      end
    end

    agent.verify
  end

  test "discover meetings helper stops at cutoff and preserves prior ids" do
    recent_date = (Time.current - 1.day).utc.strftime("%Y-%m-%d %H:%M:%S UTC")
    old_date = (Time.current - 3.days).utc.strftime("%Y-%m-%d %H:%M:%S UTC")

    recent_row = Object.new
    recent_row.define_singleton_method(:at) do |selector|
      case selector
      when ".views-field-field-calendar-date span" then { "content" => recent_date }
      when ".views-field-title" then Object.new.tap { |o| o.define_singleton_method(:text) { "City Council Meeting" } }
      when ".views-field-view-node a" then { "href" => "/meetings/recent" }
      end
    end

    old_row = Object.new
    old_row.define_singleton_method(:at) do |selector|
      case selector
      when ".views-field-field-calendar-date span" then { "content" => old_date }
      when ".views-field-title" then Object.new.tap { |o| o.define_singleton_method(:text) { "City Council Meeting" } }
      when ".views-field-view-node a" then { "href" => "/meetings/old" }
      end
    end

    page = Object.new
    page.define_singleton_method(:search) { |_selector| [ recent_row, old_row ] }
    page.define_singleton_method(:link_with) { |_args| nil }

    agent = Minitest::Mock.new
    agent.expect :user_agent_alias=, "Mac Safari", [ "Mac Safari" ]
    agent.expect :get, page, [ Scrapers::DiscoverMeetingsJob::MEETINGS_URL ]

    Mechanize.stub :new, agent do
      ids = Scrapers::DiscoverMeetingsJob.run_inline!(since: 2.days.ago)
      assert_equal [ Meeting.find_by!(detail_page_url: "https://www.two-rivers.org/meetings/recent").id ], ids
    end
  end

  test "perform enqueues transcript discovery" do
    job = Object.new
    job.define_singleton_method(:discover_meeting_ids) { |since: nil, enqueue_parse_jobs: true| [] }

    Scrapers::DiscoverMeetingsJob.stub :new, job do
      assert_enqueued_with(job: Scrapers::DiscoverTranscriptsJob) do
        Scrapers::DiscoverMeetingsJob.run_inline!
      end
    end
  end

  test "class inline helper can skip transcript enqueueing" do
    job = Object.new
    job.define_singleton_method(:discover_meeting_ids) { |since: nil, enqueue_parse_jobs: true| [ 7 ] }

    Scrapers::DiscoverMeetingsJob.stub :new, job do
      assert_equal [ 7 ], Scrapers::DiscoverMeetingsJob.run_inline!(enqueue_transcripts: false)
    end
  end

  test "repair sweep counts no-op state when nothing needs repair" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/noop", starts_at: 1.day.ago)
    meeting.mark_processing!(:meeting_page_parsed_at)
    meeting.mark_processing!(:topics_extracted_at)
    meeting.mark_processing!(:votes_extracted_at)
    meeting.mark_processing!(:committee_members_extracted_at)
    meeting.update!(processing_state: meeting.processing_state.merge(
      "topics_extraction_status" => "empty",
      "votes_extraction_status" => "empty",
      "committee_members_extraction_status" => "empty"
    ))
    document = MeetingDocument.create!(meeting: meeting, document_type: "minutes_pdf", extracted_text: "minutes", fetched_at: Time.current)
    document.file.attach(io: StringIO.new("minutes"), filename: "minutes.txt", content_type: "text/plain")
    MeetingSummary.create!(meeting: meeting, summary_type: "minutes_recap", content: "done", generation_data: { "ok" => true })

    result = nil

    assert_enqueued_with(job: Documents::AnalyzePdfJob, args: [ document.id ]) do
      result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call
    end

    assert_equal({ meetings_scoped: 1, parse_meeting_pages_enqueued: 0, document_downloads_enqueued: 1, agenda_parses_enqueued: 0, summaries_enqueued: 0, topic_extractions_enqueued: 0, vote_extractions_enqueued: 0, committee_member_extractions_enqueued: 0 }, result)
  end
end
