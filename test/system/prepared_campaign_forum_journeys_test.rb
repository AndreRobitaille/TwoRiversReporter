require "application_system_test_case"
require_relative "../support/prepared_forum_fixture"

class PreparedCampaignForumJourneysTest < ApplicationSystemTestCase
  include PreparedForumFixture

  test "an admin imports a verified forum on a phone and can revisit the original after replacement" do
    admin = User.create!(email_address: "forum-browser@example.test", admin: true, status: "active")
    admin.passkey_credentials.create!(external_id: "forum-browser-key", public_key: "public-key", sign_count: 0)
    sign_in_by_email(admin)
    visit admin_campaign_sources_path
    page.driver.browser.manage.window.resize_to(390, 844)
    click_link "Import forum"
    file = forum_parameters.fetch(:file)
    attach_file "Speaker-labeled JSON", file.path
    fill_in "Organizer", with: "Example Civic Association"
    fill_in "Forum date", with: "03/12/2024"
    fill_in "Election date", with: "04/02/2024"
    check "Speaker labels were verified against the recording."
    check "Any unlabeled words are moderator filler."
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Browser reads must not call AI" }) do
      click_button "Save forum"
      assert_selector "[data-prepared-forum]", text: "Avery Example"
      assert_selector "[data-campaign-source-text]", text: "Keep the library open on Saturdays."
      source = CampaignSource.sole
      original = source.current_version
      assert_current_path admin_campaign_source_path(source)
      assert_equal admin.id, original.submitted_by_id
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
      page.save_screenshot(Rails.root.join("tmp/screenshots/prepared-forum-mobile.png"))

      click_link "Replace transcript"
      changed = forum_export
      changed["title"] = "Corrected forum title"
      replacement = forum_parameters(changed).fetch(:file)
      attach_file "Speaker-labeled JSON", replacement.path
      check "Speaker labels were verified against the recording."
      check "Any unlabeled words are moderator filler."
      click_button "Save forum"
      assert_selector "h1", text: /Corrected forum title/i
      page.refresh
      assert_text "Complete prepared transcript"
      find("a[href='#{admin_campaign_source_path(source, version: original.id)}']").click
      assert_text "Viewing an earlier version"
      assert_selector "h1", text: /Synthetic candidate forum/i
      find("summary", text: "Original speaker file").click
      assert_selector "[data-forum-original]", text: "forum-speaker-desk"
      assert_equal 2, source.versions.count
      assert_equal 0, CampaignRequest.count
    end
  end
end
