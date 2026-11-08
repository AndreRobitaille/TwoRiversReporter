require "application_system_test_case"
require "minitest/mock"
require_relative "../support/council_formal_scenario"

class MemberFormalRecordsJourneysTest < ApplicationSystemTestCase
  include CouncilFormalScenario

  test "editor corrects a record and phone reader chooses whether to inspect its evidence" do
    setup_formal_records
    extract_formal
    sign_in_by_email(@editor)
    visit admin_council_formal_source_path(@formal_source)
    click_link "Correct record"
    fill_in "Short public case title", with: "Corrected synthetic case title"
    check "I checked the underlying formal record, the officials and Council service involved, and the text cleared for publication."
    Ai::OpenAiService.stub(:new, ->(*) { flunk "A display-title edit reuses the source analysis" }) do
      click_button "Save record"
      assert_text "Formal record saved."
      visit member_path(@member)
      page.driver.browser.manage.window.resize_to(390, 844)
      within("#formal-cases") do
        assert_no_text "Corrected synthetic case title"
        find("summary", text: "Formal complaints and findings", exact_text: true).click
        assert_text "Corrected synthetic case title"
        assert_no_text "Complaint filed"
        find("summary", text: "Corrected synthetic case title", exact_text: true).click
        assert_text "Complaint filed"
        assert_no_text @filing_quote
        find("summary", text: "Record and source", exact_text: true).click
        assert_text @filing_quote
        assert_selector "a[href='#{@formal_source.source_url}']"
      end
      assert_not_includes page.html, "PRIVATE COMPLAINANT CANARY"
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
      find("#formal-cases").scroll_to(:top)
      page.save_screenshot(ENV.fetch("FORMAL_PHONE_SCREENSHOT")) if ENV["FORMAL_PHONE_SCREENSHOT"]
      page.refresh
      assert_selector "#formal-cases:not([open])"
    end
    assert_equal 1, @calls.size
    assert_equal "Corrected synthetic case title", @formal_source.reload.title
  end
end
