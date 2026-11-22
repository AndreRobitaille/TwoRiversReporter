require "application_system_test_case"
require "minitest/mock"
require_relative "../support/council_action_scenario"

class MemberRecordedActionsJourneysTest < ApplicationSystemTestCase
  include CouncilActionScenario

  test "phone reader sees the action and can choose to open its source" do
    setup_recorded_actions
    extract_recorded_actions
    page.driver.browser.manage.window.resize_to(390, 844)
    visit member_path(@member)
    if ENV["ACTION_PHONE_SCREENSHOT"]
      page.execute_script("window.scrollTo(0, document.getElementById('recorded-actions').getBoundingClientRect().top + window.scrollY - 80)")
      page.save_screenshot(ENV.fetch("ACTION_PHONE_SCREENSHOT"))
    end
    within("#recorded-actions") do
      assert_text "Proposed a lower-cost park design; it received no second."
      assert_no_text @action_quotes.first
      find("summary").click
      assert_text @action_quotes.first
      assert_selector "a[href='#{@document.source_url}']"
      find("summary").click
      assert_no_text @action_quotes.first
    end
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
  end
end
