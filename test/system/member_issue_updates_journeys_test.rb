require "application_system_test_case"
require "minitest/mock"
require_relative "../support/council_issue_scenario"

class MemberIssueUpdatesJourneysTest < ApplicationSystemTestCase
  include CouncilIssueScenario

  test "phone reader sees a short update and opens its source without closing another" do
    setup_issue_updates
    extract_issue_updates
    page.driver.browser.manage.window.resize_to(390, 844)
    visit member_path(@member)
    assert_selector "#issue-updates [data-issue-update]", count: 2
    assert_no_text @quote
    if ENV["ISSUE_PHONE_SCREENSHOT"]
      page.execute_script("document.getElementById('issue-updates').scrollIntoView()")
      page.save_screenshot(ENV.fetch("ISSUE_PHONE_SCREENSHOT"))
    end
    within("[data-issue-update=unresolved]") { find("summary").click }
    assert_text @quote
    within("[data-issue-update=completed]") { find("summary").click }
    assert_text @quote
    assert_text "Event date: Jul 1, 2025"
    assert_selector "#issue-updates details[open]", count: 2
    assert_selector "#issue-updates a[href='#{@document.source_url}']", count: 2
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    if ENV["ISSUE_DESKTOP_SCREENSHOT"]
      page.driver.browser.manage.window.resize_to(1280, 900)
      page.execute_script("document.getElementById('issue-updates').scrollIntoView()")
      page.save_screenshot(ENV.fetch("ISSUE_DESKTOP_SCREENSHOT"))
    end
  end
end
