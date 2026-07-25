require "test_helper"

class MeetingsGatingTest < ActionDispatch::IntegrationTest
  WITHHELD = "Council directed staff to renegotiate the lakefront parking easement".freeze

  # `teaser` truncates at a word boundary within `chars` — it does not hide
  # short text that already fits under the limit (that's by design, see
  # AccessHelperTest#"leaves short text intact but still marks it faded").
  # The meeting show page teases the first highlight at 240 characters, so
  # the fixture highlight needs a leading filler clause pushing WITHHELD past
  # that boundary — otherwise a short highlight would leak in full and this
  # test would assert something the view was never designed to guarantee.
  HIGHLIGHT_FILLER = "The council spent nearly two hours reviewing the parks and recreation " \
    "capital improvement plan before turning to the marina renovation budget, weighing dock " \
    "repair costs against grant funding timelines and the maintenance backlog flagged in last " \
    "year's facilities audit.".freeze

  setup do
    @meeting = Meeting.create!(body_name: "City Council Meeting", starts_at: 3.days.ago, detail_page_url: "https://example.com/meeting")
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "headline" => "Council approved the Washington Street reconstruction contract.",
        "highlights" => [ { "text" => "#{HIGHLIGHT_FILLER} #{WITHHELD}" } ]
      }
    )
  end

  test "anonymous visitor never receives the withheld text" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    assert_response :success
    assert_no_match(/#{Regexp.escape(WITHHELD)}/, response.body)
  end

  test "anonymous visitor sees the lede and a gate" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    assert_match(/Washington Street reconstruction/, response.body)
    assert_match(/Sign in to keep reading/, response.body)
  end

  test "signed-in member receives the full page" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "reader@example.com", status: "active"))

    get meeting_path(@meeting)

    assert_match(/#{Regexp.escape(WITHHELD)}/, response.body)
    assert_no_match(/Sign in to keep reading/, response.body)
  end

  test "open mode shows everything to anonymous visitors" do
    set_access_mode("open")

    get meeting_path(@meeting)

    assert_match(/#{Regexp.escape(WITHHELD)}/, response.body)
    assert_no_match(/Sign in to keep reading/, response.body)
  end

  test "legacy recap is gated for anonymous visitors, shown to members" do
    legacy_meeting = Meeting.create!(body_name: "City Council Meeting", starts_at: 5.days.ago, detail_page_url: "https://example.com/legacy-meeting")
    legacy_meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      content: WITHHELD,
      generation_data: {}
    )

    set_access_mode("gated")
    get meeting_path(legacy_meeting)

    assert_response :success
    assert_no_match(/#{Regexp.escape(WITHHELD)}/, response.body)
    assert_match(/Sign in to keep reading/, response.body)

    sign_in_as(User.create!(email_address: "legacy-reader@example.com", status: "active"))
    get meeting_path(legacy_meeting)

    assert_match(/#{Regexp.escape(WITHHELD)}/, response.body)
    assert_no_match(/Sign in to keep reading/, response.body)
  end

  # An agenda-only meeting renders no summary at all, so the gated page body is
  # just the header. But `meeting_share_description` and `share_text` both fell
  # back to listing agenda item titles, which handed a gated visitor content the
  # topic show page withholds from them ("Coming Up" sits below the gate). Three
  # channels carried it: <meta name="description">/og:/twitter:,
  # data-share-copy-text-value, and the Facebook hook prepend.
  WITHHELD_AGENDA_TITLE = "Shoreline setback variance request".freeze

  test "agenda-only meeting withholds agenda item titles from meta and share text" do
    upcoming = Meeting.create!(body_name: "City Council Meeting", starts_at: 5.days.from_now,
      detail_page_url: "https://example.com/upcoming-meeting")
    upcoming.agenda_items.create!(title: WITHHELD_AGENDA_TITLE, order_index: 1)

    set_access_mode("gated")
    get meeting_path(upcoming)

    assert_response :success
    assert_no_match(/#{Regexp.escape(WITHHELD_AGENDA_TITLE)}/, response.body)
    # Falls all the way back to the bare body-name/date sentence.
    assert_match(/<meta name="description" content="Two Rivers City Council — [^"]*">/, response.body)

    sign_in_as(User.create!(email_address: "agenda-reader@example.com", status: "active"))
    get meeting_path(upcoming)

    assert_match(/#{Regexp.escape(WITHHELD_AGENDA_TITLE)}/, response.body)
  end

  test "open mode still lists agenda item titles for anonymous visitors" do
    upcoming = Meeting.create!(body_name: "City Council Meeting", starts_at: 5.days.from_now,
      detail_page_url: "https://example.com/upcoming-open-meeting")
    upcoming.agenda_items.create!(title: WITHHELD_AGENDA_TITLE, order_index: 1)

    set_access_mode("open")
    get meeting_path(upcoming)

    assert_match(/#{Regexp.escape(WITHHELD_AGENDA_TITLE)}/, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
