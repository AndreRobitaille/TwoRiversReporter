require "application_system_test_case"
require_relative "../support/campaign_source_fixture"

class CampaignSourceIntakeJourneysTest < ApplicationSystemTestCase
  include CampaignSourceFixture

  test "admin saves a shared questionnaire on a phone and can revisit its original after a correction" do
    admin = User.create!(email_address: "campaign-browser@example.com", admin: true, status: "active")
    admin.passkey_credentials.create!(external_id: "campaign-browser-key", public_key: "public-key", sign_count: 0)
    sign_in_by_email(admin)
    visit admin_members_path
    click_link "Campaign sources"
    click_link "Add article"
    page.driver.browser.manage.window.resize_to(390, 844)
    fill_in "Article title", with: campaign_article_attributes[:title]
    fill_in "Publisher link", with: campaign_article_attributes[:source_url]
    fill_in "Publisher", with: campaign_article_attributes[:publisher], exact: true
    fill_in "Election date", with: "04/06/2027"
    fill_in "Article text", with: campaign_article_attributes[:body]
    click_button "Save article"
    assert_selector "[data-campaign-source-text]", text: "questionnaire-cobalt"
    source = CampaignSource.sole
    original = source.current_version
    assert_equal Date.new(2027, 4, 6), source.election_on
    assert_current_path admin_campaign_source_path(source)
    assert_text "questionnaire-cobalt"
    assert_text "Unknown"
    assert_text "April 6, 2027"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    page.save_screenshot(Rails.root.join("tmp/screenshots/campaign-source-mobile.png"))

    click_link "Edit article"
    select "Selected excerpts", from: "Text included"
    fill_in "Article text", with: "Corrected final answer - questionnaire-cobalt"
    click_button "Save article"
    assert_text "Corrected final answer"
    page.refresh
    assert_text "Selected excerpts"
    find("a[href='#{admin_campaign_source_path(source, version: original.id)}']").click
    assert_text "Viewing an earlier version"
    assert_text "The second paragraph qualifies this answer"
    assert_equal 2, source.versions.count
  end
end
