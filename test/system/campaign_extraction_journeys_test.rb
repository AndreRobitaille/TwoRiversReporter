require "application_system_test_case"
require_relative "../support/campaign_extraction_scenario"

class CampaignExtractionJourneysTest < ApplicationSystemTestCase
  include CampaignExtractionScenario

  test "admin reads every extracted participant and opens a supporting passage on a phone" do
    setup_campaign_extraction
    admin = User.create!(email_address: "campaign-extraction-browser@example.test", admin: true, status: "active")
    admin.passkey_credentials.create!(external_id: "campaign-extraction-browser-key", public_key: "public-key", sign_count: 0)
    budget = campaign_budget
    with_campaign_transport { ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: budget.id) }
    sign_in_by_email(admin)
    visit admin_members_path
    click_link "Campaign sources"
    click_link @source.title
    page.driver.browser.manage.window.resize_to(390, 844)
    within "[data-campaign-extraction]" do
      assert_selector "[data-campaign-statement]", count: 5
      assert_selector "h3", text: /Jordan Example/i
      assert_selector "h3", text: /Taylor Example/i
      assert_selector "h3", text: /Morgan Example/i
      assert_text "Before the next budget."
      assert_text "If grant funding is available."
      first("summary", text: "Supporting passage").click
      assert_selector "blockquote", text: "Repair neighborhood water lines.", visible: true
      assert_text "Morgan did not answer the funding question."
    end
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    page.execute_script("window.scrollTo(0, 0)")
    page.save_screenshot(Rails.root.join("tmp/screenshots/campaign-extraction-mobile.png"))
    page.refresh
    assert_selector "[data-campaign-statement]", count: 5
    assert_equal 1, @calls.size
  end
end
