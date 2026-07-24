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

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
