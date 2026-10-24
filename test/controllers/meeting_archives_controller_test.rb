require "test_helper"

class MeetingArchivesControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 24, 12)
    @september = create_meeting("City Council", Time.zone.local(2026, 9, 30, 23, 30))
    @october = create_meeting("Plan Commission", Time.zone.local(2026, 10, 1))
    @old = create_meeting("Library Board", Time.zone.local(2025, 12, 8))
    @future = create_meeting("Future Board", 1.day.from_now)
  end

  test "browse links retain old meetings and respect the local month boundary" do
    get meetings_path
    assert_select "a[href=?]", meeting_archive_path
    get meeting_archive_path
    assert_select "a[href=?]", month_path(2026, 9), text: "September 2026"
    assert_select "a[href=?]", month_path(2025, 12), text: "December 2025"
    assert_select "a[href*='/archive/2026/08']", count: 0

    get month_path(2026, 9)
    assert_response :success
    assert_select "link[rel=canonical][href=?]", "https://tworiversmatters.com#{month_path(2026, 9)}"
    assert_select "a[href=?]", meeting_path(@september)
    assert_select "a[href=?]", meeting_path(@october), count: 0
    assert_select "nav[aria-label='Archive months'] a[href=?]", month_path(2025, 12)
    assert_select "nav[aria-label='Archive months'] a[href=?]", month_path(2026, 10)

    get month_path(2026, 10)
    assert_select ".meeting-archive-list a[href=?]", meeting_path(@october)
    assert_select ".meeting-archive-list a[href=?]", meeting_path(@future), count: 0
    travel 2.days
    get month_path(2026, 10)
    assert_select ".meeting-archive-list a[href=?]", meeting_path(@future)
  end

  test "archive uses the same canonical duplicate including cancellation and content precedence as detail pages" do
    cancelled = create_meeting("Plan Commission (CANCELED)", @october.starts_at)
    get month_path(2026, 10)
    assert_select ".meeting-archive-list a[href=?]", meeting_path(cancelled), count: 1
    assert_select ".meeting-archive-list .badge", text: "Canceled"
    assert_select ".meeting-archive-list a[href=?]", meeting_path(@october), count: 0
    get meeting_path(@october)
    assert_redirected_to meeting_path(cancelled)

    enriched = create_meeting(@september.body_name, @september.starts_at)
    enriched.meeting_summaries.create!(summary_type: "minutes_recap", content: "Distinctive full analysis")
    get month_path(2026, 9)
    assert_select ".meeting-archive-list a[href=?]", meeting_path(enriched), count: 1
    assert_select ".meeting-archive-list a[href=?]", meeting_path(@september), count: 0
  end

  test "large months have bounded self canonical pages with no lost or repeated meetings" do
    52.times { |i| create_meeting("Archive Board #{i}", Time.zone.local(2026, 8, 1) + i.hours) }
    get month_path(2026, 8)
    first = css_select(".meeting-archive-list a").map { |a| a["href"] }
    assert_equal 50, first.size
    get month_path(2026, 8), params: { page: 2 }
    assert_equal first, css_select(".meeting-archive-list a").map { |a| a["href"] }
    second_page = meeting_archive_month_path(year: 2026, month: "08", page: 2)
    assert_select "a[href=?]", second_page, text: "Next page"
    get second_page
    assert_response :success
    second = css_select(".meeting-archive-list a").map { |a| a["href"] }
    assert_equal 2, second.size
    assert_empty first & second
    assert_select "a[href=?]", month_path(2026, 8), text: "Previous page"
    assert_select "link[rel=canonical][href=?]", "https://tworiversmatters.com#{second_page}"
    assert_select "title", text: /Page 2/
    get meeting_archive_month_path(year: 2026, month: "08", page: 1)
    assert_redirected_to month_path(2026, 8)
    assert_response :moved_permanently
  end

  test "empty archive is useful and nonexistent months pages and formats are rejected" do
    [ "/meetings/archive/2026/13", "/meetings/archive/no/09", month_path(2026, 8),
      meeting_archive_month_path(year: 2026, month: "09", page: 2) ].each do |path|
      get path
      assert_response :not_found
    end
    get "#{month_path(2026, 9)}.json"
    assert_response :not_acceptable
    Meeting.destroy_all
    get meeting_archive_path
    assert_response :success
    assert_select "p", text: "No past meetings are available yet."
    assert_select "a[href=?]", meetings_path
  end

  private

    def create_meeting(body, time)
      Meeting.create!(body_name: body, starts_at: time, detail_page_url: "https://example.com/#{SecureRandom.hex(8)}")
    end

    def month_path(year, month)
      meeting_archive_month_path(year: year, month: format("%02d", month))
    end
end
