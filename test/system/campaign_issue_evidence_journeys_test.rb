require "application_system_test_case"
require "minitest/mock"
require_relative "../support/campaign_issue_evidence_scenario"

class CampaignIssueEvidenceJourneysTest < ApplicationSystemTestCase
  include CampaignIssueEvidenceScenario

  test "phone reader distinguishes unsuccessful work from issue outcome and chooses source details" do
    setup_issue_matching
    match_issue_evidence
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Saved matching has no browsing cost" }) do
      visit member_path(@jordan)
      page.driver.browser.manage.window.resize_to(390, 844)
      click_link "Campaign priorities", exact: true
      assert_current_path(member_path(@jordan)) { |url| url.fragment == "campaign-record" }
      assert_no_selector "html[aria-busy='true']"
      issue = find("[data-campaign-topic='#{@water.id}']")
      issue.find(".member-campaign-summary").click
      within("[data-campaign-actions-for='#{@specific.id}']") do
        assert_text "Recorded work"
        assert_text "request did not advance"
        assert_text "Issue update"
        assert_text "rule was not adopted"
        assert_no_text @advocacy_quote
        issue.scroll_to(:top)
        page.save_screenshot(ENV.fetch("ISSUE_MATCH_PHONE_SCREENSHOT").sub(".png", "-closed.png")) if ENV["ISSUE_MATCH_PHONE_SCREENSHOT"]
        find("summary", text: "Supporting details", exact_text: true).click
        assert_text @advocacy_quote
        assert_text @outcome_quote
        assert_selector "a[href='#{@document.source_url}']"
      end
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
      issue.scroll_to(:top)
      page.save_screenshot(ENV.fetch("ISSUE_MATCH_PHONE_SCREENSHOT")) if ENV["ISSUE_MATCH_PHONE_SCREENSHOT"]
      page.refresh
      assert_no_text @advocacy_quote
      assert_selector "[data-campaign-issue-evidence]", count: 2, visible: :all
    end
    assert_equal 2, @calls.size
  end
end
