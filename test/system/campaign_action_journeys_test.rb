require "application_system_test_case"
require_relative "../support/campaign_action_scenario"

class CampaignActionJourneysTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  include CampaignActionScenario

  test "a resident can inspect the exact matched statement vote and minutes without losing the campaign context" do
    setup_campaign_actions
    review_campaign_actions
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Browsing must reuse saved comparisons" }) do
      visit member_path(@jordan)
      page.driver.browser.manage.window.resize_to(390, 844)
      click_link "Campaign priorities", exact: true
      issue = find("[data-campaign-topic='#{@water.id}']")
      issue.find(".member-campaign-summary").click
      assert_text @specific.data.fetch("summary")
      within "[data-campaign-actions-for='#{@specific.id}']" do
        assert_text "Jordan Example: Yes"
        assert_text "Council: Failed"
        assert_no_text @quote
        find("summary", text: "Supporting minutes passage").click
        assert_text @quote
        click_link "Meeting and sources"
      end
      assert_current_path meeting_path(@vote.motion.meeting)
      page.go_back
      assert_selector "[data-campaign-action='#{@vote.id}']"
      assert_no_selector "[data-campaign-actions-for='#{@broad.id}']", visible: :all
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
      page.refresh
      assert_selector "[data-campaign-action='#{@vote.id}']", visible: :all
      assert_no_text @quote
    end
    assert_equal 1, @calls.size
  end
end
