require "application_system_test_case"
require_relative "../support/campaign_activity_scenario"

class MemberCampaignActivityJourneysTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  include CampaignActivityScenario

  test "a reader keeps campaign sources open independently and reaches votes in the main record" do
    setup_campaign_activity(separate_issues: true)
    [ 2, 9, 16, 23 ].each do |day|
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
      assert_current_path(member_path(@jordan)) { |url| url.fragment == "campaign-record" }
      assert_no_selector "html[aria-busy='true']"
      assert_selector ".member-campaign-issue[open]", count: 1
      assert_no_selector ".member-campaign-evidence[open]"
      assert_no_text "Water renewal decision 23"
      assert_no_text "Follow this issue"
      first_issue = find(".member-campaign-issue[open]")["data-campaign-topic"]
      find(".member-campaign-issue:not([open]) > summary").click
      assert_selector ".member-campaign-issue[open]", count: 2
      assert_no_selector ".member-campaign-issue a", visible: :all
      other_issue = find(".member-campaign-issue:not([data-campaign-topic='#{first_issue}'])")
      other_issue.find(".member-campaign-summary").click
      assert_selector ".member-campaign-issue[open]", count: 1
      assert_selector "[data-campaign-topic='#{first_issue}'][open]"
      find("#campaign-record > .member-campaign-evidence > summary").click
      find(".member-campaign-card > summary", match: :first).click
      assert_link "Example Newspaper"
      assert_no_selector "#campaign-record [data-campaign-vote]", visible: :all
      click_link "Voting record", exact: true
      assert_current_path(member_path(@jordan)) { |url| url.fragment == "voting-record" }
      assert_no_selector "html[aria-busy='true']"
      within ".member-profile-primary" do
        click_link "Motion to adopt the resolution", match: :first
      end
      assert_current_path %r{/meetings/}
      page.go_back
      page.refresh
      assert_no_selector ".member-other-votes[open]"
      assert_selector ".member-campaign-issue[open]", count: 1
      assert_no_selector ".member-campaign-evidence[open]"
      assert_no_selector "#campaign-record [data-campaign-vote]", visible: :all
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
      find("#campaign-record").scroll_to(:top)
      page.save_screenshot(Rails.root.join("tmp/screenshots/member-campaign-activity-mobile.png"))
    end
    assert_equal 2, @calls.size
  end
end
