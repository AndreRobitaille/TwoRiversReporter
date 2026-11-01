require "test_helper"

class MeetingCardDatesTest < ActionDispatch::IntegrationTest
  # Explicit UTC inputs and local labels keep the expectations independent of
  # Active Record's casting and the formatter under test.
  {
    "standard time at UTC midnight" => [ "2026-11-03T00:00:00Z", "Nov 2", "November 2, 2026 · 6:00 PM" ],
    "daylight time after UTC midnight" => [ "2026-07-02T00:30:00Z", "Jul 1", "July 1, 2026 · 7:30 PM" ],
    "month boundary before the fall clock change" => [ "2026-11-01T00:30:00Z", "Oct 31", "October 31, 2026 · 7:30 PM" ],
    "year boundary" => [ "2027-01-01T00:00:00Z", "Dec 31", "December 31, 2026 · 6:00 PM" ],
    "daytime control" => [ "2026-11-02T18:00:00Z", "Nov 2", "November 2, 2026 · 12:00 PM" ]
  }.each do |scenario, (instant, label, detail_label)|
    test "cards agree with the meeting record for #{scenario}" do
      travel_to(Time.iso8601(instant) - 1.day) do
        create_meeting_topics(instant)

        assert_home_dates(label)

        get topics_path
        assert_response :success
        assert_topic_dates(label)

        get topics_path, params: { q: "calendar boundary" }
        assert_response :success
        assert_topic_dates(label)

        get committee_path(@committee.slug)
        assert_response :success
        @topics.each do |topic|
          assert_select "a.committee-activity-item[href=?] .committee-activity-date", topic_path(topic), text: label
        end

        get meeting_path(@meeting)
        assert_response :success
        assert_select ".meeting-article-date", text: detail_label
        assert_equal instant, @meeting.reload.starts_at.utc.iso8601
      end
    end
  end

  test "older topic cards keep local dates in HTML and Turbo append responses" do
    travel_to(Time.utc(2026, 11, 1, 18)) do
      create_meeting_topics("2026-11-03T00:00:00Z")
      @topics.each { |topic| topic.update!(last_activity_at: 40.days.ago) }

      get topics_path
      assert_response :success
      assert_topic_dates("Nov 2")

      get topics_path(format: :turbo_stream)
      assert_response :success
      assert_select "turbo-stream[action='append'][target='all-topics-cards']" do
        assert_topic_dates("Nov 2")
      end
    end
  end

  test "public and member cards use the same local date in gated mode" do
    travel_to(Time.utc(2026, 11, 1, 18)) do
      create_meeting_topics("2026-11-03T00:00:00Z")
      SiteSetting.create!(access_mode: "gated", singleton_guard: 0)

      assert_home_dates("Nov 2")
      get topics_path
      assert_response :success
      assert_topic_dates("Nov 2")

      sign_in_as(User.create!(email_address: "calendar-reader@example.test", status: "active"))
      assert_home_dates("Nov 2")
      get topics_path
      assert_response :success
      assert_topic_dates("Nov 2")
      get committee_path(@committee.slug)
      assert_response :success
      assert_select ".committee-activity-date", text: "Nov 2", count: 2
    end
  end

  private

    def create_meeting_topics(instant)
      @committee = Committee.create!(name: "City Council", slug: "calendar-council", committee_type: "city", status: "active")
      @meeting = Meeting.create!(body_name: "City Council Meeting", committee: @committee,
        starts_at: Time.iso8601(instant), detail_page_url: "https://example.test/calendar-meeting")
      @topics = [ 5, 3 ].map do |impact|
        topic = Topic.create!(name: "calendar boundary #{impact}", status: "approved", lifecycle_status: "active",
          resident_impact_score: impact, last_activity_at: Time.current)
        item = @meeting.agenda_items.create!(title: "Calendar proposal #{impact}")
        AgendaItemTopic.create!(topic: topic, agenda_item: item)
        topic
      end
      older_meeting = Meeting.create!(body_name: "Previous Council Meeting", committee: @committee,
        starts_at: @meeting.starts_at - 2.days, detail_page_url: "https://example.test/older-calendar-meeting")
      older_item = older_meeting.agenda_items.create!(title: "Earlier calendar proposal")
      AgendaItemTopic.create!(topic: @topics.first, agenda_item: older_item)
    end

    def assert_home_dates(label)
      get root_path
      assert_response :success
      assert_select "a.top-story[href=?] .story-meta", topic_path(@topics.first), text: "#{label} · City Council"
      assert_select "a.wire-card[href=?] .wire-meta", topic_path(@topics.last), text: "#{label} · City Council"
      assert_select "a.nextup-card[href=?] .date-month", meeting_path(@meeting), text: label.split.first
      assert_select "a.nextup-card[href=?] .date-day", meeting_path(@meeting), text: label.split.last
    end

    def assert_topic_dates(label)
      @topics.each do |topic|
        assert_select "a.topics-card[href=?] .topics-card-meta", topic_path(topic), text: "#{label} · City Council"
      end
    end
end
