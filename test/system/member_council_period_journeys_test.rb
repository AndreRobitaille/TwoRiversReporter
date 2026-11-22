require "application_system_test_case"
require_relative "../support/council_period_setup"

class MemberCouncilPeriodJourneysTest < ApplicationSystemTestCase
  include CouncilPeriodSetup

  test "resident selects an older period and keeps it through views pages and a meeting visit" do
    setup_council_periods
    page.driver.browser.manage.window.resize_to(390, 844)
    visit member_path(@member)
    assert_selector ".member-vote-motion", text: "Current road project 25"
    select "Apr 20, 2021 – Apr 15, 2024", from: "Council record"
    click_button "Show record"
    assert_selector "#council-attendance [data-attendance-status=absent] dd", text: "1", exact_text: true
    assert_selector ".member-vote-motion", text: "Earlier road project 25"
    assert_no_text "Current road project"
    click_link "All recorded votes"
    assert_selector ".member-recorded-motion", count: 25
    assert_select_value "2021-election"
    within(".member-vote-pages") { click_link "2", exact: true }
    assert_selector ".member-recorded-motion", count: 1, text: "Earlier road project 0"
    click_link "Meeting and sources"
    assert_current_path meeting_path(@old_meeting)
    page.go_back
    assert_selector ".member-recorded-motion", text: "Earlier road project 0"
    click_link "Featured votes"
    assert_select_value "2021-election"
    assert_selector ".member-vote-motion", text: "Earlier road project 25"
    select "All available records", from: "Council record"
    click_button "Show record"
    assert_select_value "all"
    assert_selector ".member-vote-motion", text: "Current road project 25"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
  end

  private

  def assert_select_value(value)
    assert_equal value, find("select[name=term]").value
  end
end
