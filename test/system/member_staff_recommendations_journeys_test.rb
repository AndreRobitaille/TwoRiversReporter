require "application_system_test_case"
require "minitest/mock"
require_relative "../support/council_recommendation_scenario"

class MemberStaffRecommendationsJourneysTest < ApplicationSystemTestCase
  include CouncilRecommendationScenario

  test "phone reader opens a fraction follows evidence and returns to the same term" do
    setup_recommendations
    extract_recommendations
    page.driver.browser.manage.window.resize_to(390, 844)
    visit member_path(@member, term: @period.period_key)
    within("#staff-recommendations") do
      assert_no_text "Alex Manager"
      find("summary").click
      assert_text(/Alex Manager/i)
      first("a").click
    end
    assert_text "1 of 1 comparable votes"
    page.save_screenshot(ENV.fetch("STAFF_PHONE_SCREENSHOT")) if ENV["STAFF_PHONE_SCREENSHOT"]
    assert_no_text @recommendation["quote"]
    find("summary", text: "Recommendation and source").click
    assert_text @recommendation["quote"]
    assert_selector "a[href='#{@document.source_url}']"
    click_link "Divided votes"
    assert_text "1 of 1 comparable votes"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    click_link "Back to #{@member.name}'s record"
    assert_equal @period.period_key, URI.decode_www_form(URI.parse(page.current_url).query).to_h.fetch("term")
    assert_selector "#staff-recommendations:not([open])"
  end
end
