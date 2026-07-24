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
