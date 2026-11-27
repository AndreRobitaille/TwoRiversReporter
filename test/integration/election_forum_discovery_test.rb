require "test_helper"
require "minitest/mock"

class ElectionForumDiscoveryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "a city announcement becomes a dated recording with captions in the speaker desk" do
    travel_to Time.zone.local(2027, 2, 18, 7, 30)
    admin = User.create!(email_address: "forum-watcher@example.test", admin: true, status: "active")
    sign_in_as_admin(admin)
    url = "https://www.two-rivers.org/council/agenda"
    meeting = Meeting.create!(body_name: "City Council Meeting", starts_at: 1.day.ago, detail_page_url: url)
    text = "League of Women Voters, City Council Candidates Forum, Thursday, March 4, 2027, 7 PM. " \
      "Two Rivers Business Association, School Board Candidates Forum, Thursday, March 4, 2027."
    meeting.meeting_documents.create!(source_url: url, document_type: "agenda_pdf", extracted_text: text)
    key = :discover_spring_forums
    routine = SolidQueue::RecurringTask.from_configuration(key.to_s, **Rails.application.config_for(:recurring, env: "production").fetch(key))
    assert routine.valid?, routine.errors.full_messages.to_sentence
    assert_equal Time.zone.local(2027, 2, 19, 7, 30), routine.next_time_after(Time.current)
    perform_enqueued_jobs(only: DiscoverElectionForumsJob) { routine.enqueue(at: Time.current) }
    forum = ElectionForum.sole
    assert_equal [ Date.new(2027, 3, 4), "League of Women Voters", url ], [ forum.held_on, forum.organizer, forum.announcement_url ]
    get admin_elections_path(year: 2027)
    assert_select "a[href=?]", url, text: "City announcement"
    assert_select "h3", text: "League of Women Voters forum · March 4"
    assert_select "a", text: "Label speakers", count: 0

    travel_to Time.zone.local(2027, 3, 6)
    sign_in_as_admin(admin)
    id = SecureRandom.hex(6).first(11)
    video_url = ElectionForum.video_url(id)
    title = "League of Women Voters Two Rivers City Council Candidate Forum"
    listing = "#{id} | #{title}\nWrongRace01 | League of Women Voters School Board Candidate Forum"
    meta = '<meta itemprop="startDate" content="2027-03-05T01:00:00Z"><meta itemprop="endDate" content="2027-03-05T02:30:00Z">'
    ok = Struct.new(:success?).new(true)
    file = Rails.root.join("storage/election-captions", "#{id}.vtt")
    fetch = lambda do |address|
      assert_equal video_url, address
      Struct.new(:success?, :body).new(true, meta)
    end
    Documents::TranscriptDownloader.stub(:run_yt_dlp, [ listing, "", ok ]) do
      Faraday.stub(:get, fetch) do
        assert_enqueued_with(job: DiscoverElectionForumsJob, args: [ 2027 ]) { post admin_election_find_forums_path(year: 2027) }
        follow_redirect!
        assert_select "[role=status]", text: /Forum search queued/
        assert_enqueued_with(job: PrepareElectionForumCaptionsJob, args: [ forum.id, id ]) do
          perform_enqueued_jobs(only: DiscoverElectionForumsJob)
        end
        assert_equal [ id ], forum.reload.recordings.keys
        get admin_elections_path(year: 2027)
        assert_select "section:has(#election-done) a[href=?]", video_url, text: "Watch recording"
        assert_select "a", text: "Upload captions", count: 0
        with_published_captions(available: false) { perform_enqueued_jobs(only: PrepareElectionForumCaptionsJob) }
        get admin_elections_path(year: 2027)
        assert_select "a", text: "Upload captions"
        with_published_captions do
          perform_enqueued_jobs { post admin_election_find_forums_path(year: 2027) }
        end
        get admin_elections_path(year: 2027)
        action = css_select("a").find { |a| a.text == "Label speakers" }
        assert action, "A new recording should open in the speaker desk"
        get action["href"]
        assert_select "#reading-title", text: title
        caption_url = css_select(".speaker-desk").first["data-recording"]
        get caption_url
        assert_response :success
        assert_includes response.body, "What are your priorities?"
        original = file.stat
        assert_no_enqueued_jobs(only: PrepareElectionForumCaptionsJob) do
          perform_enqueued_jobs(only: DiscoverElectionForumsJob) { post admin_election_find_forums_path(year: 2027) }
        end
        assert_equal original.mtime, file.mtime
        assert_equal 1, ElectionForum.count
        assert_empty CampaignSource.all
      end
    end
    delete public_session_path
    assert_no_enqueued_jobs(only: DiscoverElectionForumsJob) { post admin_election_find_forums_path(year: 2027) }
  ensure
    FileUtils.rm_f(file) if file
  end

  test "a scheduled run outside forum season does no discovery" do
    [ Date.new(2027, 1, 31), Date.new(2027, 4, 7) ].each do |day|
      travel_to(day) do
        Campaigns::ForumDiscovery.stub(:collect_notices, ->(*) { flunk "Unexpected out-of-season forum search" }) do
          assert_nil DiscoverElectionForumsJob.perform_now
        end
      end
    end
  end

  private

  def with_published_captions(available: true)
    previous = ENV["YT_DLP"]
    Dir.mktmpdir do |dir|
      cli = Pathname.new(dir).join("yt-dlp")
      cli.write(<<~'SCRIPT')
        #!/usr/bin/env ruby
        abort unless ARGV.include?("--write-subs") && ARGV.include?("--skip-download")
        path = ARGV.fetch(ARGV.index("-o") + 1).sub("%(ext)s", "en.vtt")
        File.write(path, "WEBVTT\n\n00:00:01.000 --> 00:00:03.000\nWhat are your priorities?\n")
      SCRIPT
      cli.write("#!/bin/sh\nexit 0\n") unless available
      cli.chmod(0o700)
      ENV["YT_DLP"] = cli.to_s
      yield
    end
  ensure
    ENV["YT_DLP"] = previous
  end
end
