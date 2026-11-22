require "application_system_test_case"
require_relative "../support/briefing_withdrawal_scenario"

class CouncilBriefingWithdrawalJourneyTest < ApplicationSystemTestCase
  include BriefingWithdrawalScenario

  test "resident follows topic evidence after a corrected briefing is withdrawn" do
    SiteSetting.instance.update!(access_mode: "open")
    build_withdrawal_scenario
    without_paid_providers do
      visit topics_path
      find("a[href='#{topic_path(@topic)}']").click
      assert_text STORY
      assert_selector "meta[name='description'][content='#{CLAIM}']", visible: :all
      withdraw_decision
      visit current_path
      assert_selector "h1", text: @topic.name.upcase
      assert_no_text STORY
      assert_no_selector "meta[name='description'][content='#{CLAIM}']", visible: :all
      assert_text "The generated analysis was withdrawn after its supporting evidence changed."
      assert_no_text "No meeting activity recorded for this topic yet."
      within ".topic-article-section--record" do
        find("a[href='#{meeting_path(@meeting)}']").click
      end
      assert_current_path meeting_path(@meeting)
      assert_selector "a[href='#{@document.source_url}']"
      visit topics_path
      fill_in "q", with: CLAIM
      click_button "Search"
      assert_text "No topics found"
      assert_no_selector "a[href='#{topic_path(@topic)}']"
      visit topic_path(@other)
      assert_text "Synthetic maple story"
    end
  end
end
