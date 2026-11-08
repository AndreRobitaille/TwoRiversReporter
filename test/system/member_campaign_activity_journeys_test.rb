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
    other = activity_vote(date: Date.new(2025, 6, 30), description: "Maintain the public pier")
    other.motion.agenda_item.topics.clear
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Reading existing activity must stay offline" }) do
      visit member_path(@jordan)
      page.driver.browser.manage.window.resize_to(1280, 900)
      assert_selector ".member-profile-sidebar #campaign-record", count: 1
      assert page.evaluate_script("document.querySelector('.member-profile-sidebar').getBoundingClientRect().left >= document.querySelector('.member-profile-primary').getBoundingClientRect().right"),
        "Campaign context should sit beside the main record on desktop"
      assert page.evaluate_script("document.querySelector('.member-profile-sidebar').getBoundingClientRect().width < document.querySelector('.member-profile-primary').getBoundingClientRect().width")
      assert_no_selector ".member-other-votes[open]"
      assert_no_text "Maintain the public pier"
      find(".member-other-votes > summary").click
      assert_text "Maintain the public pier"
      find(".member-other-votes > summary").click
      page.driver.browser.manage.window.resize_to(390, 844)
      assert page.evaluate_script("document.querySelector('.member-profile-sidebar').getBoundingClientRect().top >= document.querySelector('.member-profile-primary').getBoundingClientRect().bottom"),
        "The main record should precede campaign context on a phone"
      click_link "Campaign priorities", exact: true
      assert_selector ".member-campaign-issue[open]", count: 1
      assert_no_selector ".member-campaign-evidence[open]"
      assert_text /What they said/i
      assert_text /Related Council votes/i
      assert_text /Council result/i
      within "[data-campaign-activity]" do
        assert_selector ".member-campaign-actions li", count: 2
        assert_text "Water renewal decision 23"
        assert_text "Water renewal decision 16"
        assert_no_text "Water renewal decision 2", exact: true
        assert_no_selector "[data-campaign-vote]", visible: true
        find("summary", text: "Statements and decisions", exact_text: true).click
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
      assert_no_selector ".member-other-votes[open]"
      assert_selector ".member-campaign-issue[open]", count: 1
      assert_no_selector ".member-campaign-evidence[open]"
      assert_selector "[data-campaign-activity]", count: 1
      assert_selector ".member-campaign-actions li", count: 2
      assert_no_selector "[data-campaign-vote]", visible: true
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
      find("[data-campaign-activity]").scroll_to(:top)
      page.save_screenshot(Rails.root.join("tmp/screenshots/member-campaign-activity-mobile.png"))
    end
    assert_equal 2, @calls.size
  end
end
