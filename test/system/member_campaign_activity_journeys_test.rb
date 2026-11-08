require "application_system_test_case"
require_relative "../support/campaign_activity_scenario"

class MemberCampaignActivityJourneysTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  include CampaignActivityScenario

  test "a reader expands related Council votes and returns from their meeting on a phone" do
    setup_campaign_activity
    records = [ 2, 9, 16, 23 ].map do |day|
      activity_vote(date: Date.new(2025, 6, day), agenda_title: "Water renewal decision #{day}",
        description: "Motion to adopt the resolution")
    end
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Reading existing activity must stay offline" }) do
      visit member_path(@jordan)
      page.driver.browser.manage.window.resize_to(390, 844)
      within "[data-campaign-activity]" do
        assert_selector "[data-campaign-vote]", count: 3, visible: true
        assert_no_selector "[data-campaign-vote='#{records.first.id}']", visible: true
        find("summary", text: "Show 1 more related vote").click
        assert_selector "[data-campaign-vote]", count: 4, visible: true
        within "[data-campaign-vote='#{records.first.id}']" do
          assert_text "Water renewal decision 2"
          assert_text "Jordan Example: No"
          assert_text "Council: Passed"
          find("summary", text: "Motion wording").click
          assert_text "Motion to adopt the resolution"
          click_link "Meeting and sources"
        end
      end
      assert_current_path meeting_path(records.first.motion.meeting)
      page.go_back
      page.refresh
      assert_selector "[data-campaign-activity]", count: 1
      assert_selector "[data-campaign-vote]", count: 3, visible: true
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
      find("[data-campaign-activity]").scroll_to(:top)
      page.save_screenshot(Rails.root.join("tmp/screenshots/member-campaign-activity-mobile.png"))
    end
    assert_equal 2, @calls.size
  end
end
