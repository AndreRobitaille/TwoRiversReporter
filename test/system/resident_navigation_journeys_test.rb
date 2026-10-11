require "application_system_test_case"

class ResidentNavigationJourneysTest < ApplicationSystemTestCase
  setup do
    @topic = Topic.create!(name: "browser water improvement", status: "approved",
      lifecycle_status: "active", resident_impact_score: 5, last_activity_at: 1.day.ago)
    @meeting = Meeting.create!(body_name: "City Council Meeting", starts_at: 5.days.from_now,
      detail_page_url: "https://example.com/browser-council")
    item = @meeting.agenda_items.create!(title: "Water improvement proposal")
    AgendaItemTopic.create!(agenda_item: item, topic: @topic)
  end

  test "anonymous resident follows homepage topic and meeting links in open mode" do
    assert_resident_navigation
  end

  test "anonymous resident follows homepage topic and meeting links in gated mode" do
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    assert_resident_navigation
  end

  test "approved member follows homepage topic and meeting links in gated mode" do
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    sign_in_by_email(User.create!(email_address: "navigation-member@example.com", status: "active"))
    assert_resident_navigation
  end

  private

    def assert_resident_navigation
      visit root_path
      find("a.top-story[href='#{topic_path(@topic)}']").click
      assert_current_path topic_path(@topic)
      assert_selector "h1", text: /#{Regexp.escape(@topic.name)}/i

      visit root_path
      find("a.nextup-card[href='#{meeting_path(@meeting)}']").click
      assert_current_path meeting_path(@meeting)
      assert_selector "h1", text: /Council/i

      within ".site-nav" do
        click_link "Topics", exact: true
      end
      assert_current_path topics_path
      assert_selector "a[href='#{topic_path(@topic)}']", text: /#{Regexp.escape(@topic.name)}/i

      within ".site-nav" do
        click_link "Meetings", exact: true
      end
      assert_current_path meetings_path
      assert_selector "a[href='#{meeting_path(@meeting)}']"
    end
end
