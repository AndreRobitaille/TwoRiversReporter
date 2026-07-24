require "test_helper"

class MeetingsIndexGatingTest < ActionDispatch::IntegrationTest
  HEADLINE = "Council approved the Washington Street reconstruction contract " \
             "after residents raised concerns about driveway access during the " \
             "eighteen month build window and asked staff to return with options".freeze

  setup do
    @meeting = Meeting.create!(body_name: "City Council Meeting", starts_at: 2.days.ago, detail_page_url: "https://example.com/meeting")
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: { "headline" => HEADLINE }
    )
  end

  test "anonymous visitor gets only the first 90 characters of a card headline" do
    set_access_mode("gated")

    get meetings_path

    assert_response :success
    assert_match(/Council approved the Washington Street/, response.body)
    assert_no_match(/asked staff to return with options/, response.body)
    assert_match(/teaser-fade/, response.body)

    # Pin the fade modifier: a wrong `fade:` value (e.g. :block) would still
    # pass every assertion above, but would render "teaser-fade" alone
    # instead of "teaser-fade teaser-fade--inline".
    assert_match(/teaser-fade teaser-fade--inline/, response.body)

    # Pin the truncation boundary itself. HEADLINE's first 194 characters,
    # measured directly (irb: `String.new(HEADLINE).truncate(90, separator:
    # " ", omission: "")`), truncate at chars: 90 to exactly:
    #   "Council approved the Washington Street reconstruction contract after
    #    residents raised" (85 chars — the word-boundary truncate backs off
    #    from 90 to the last space)
    # "raised" is the word offsets 79-85 (last word kept); "concerns" is the
    # word at offsets 86-94 (first word cut). A wrong chars: value (e.g. 150,
    # which keeps "concerns") would still pass every assertion above but
    # would fail these two.
    assert_match(/raised/, response.body)
    assert_no_match(/concerns/, response.body)
  end

  test "signed-in member gets the whole headline" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "card-reader@example.com", status: "active"))

    get meetings_path

    assert_match(/asked staff to return with options/, response.body)
  end

  test "open mode shows the whole headline anonymously" do
    set_access_mode("open")

    get meetings_path

    assert_match(/asked staff to return with options/, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
