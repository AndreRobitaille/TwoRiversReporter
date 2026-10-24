require "application_system_test_case"

class MeetingArchiveJourneysTest < ApplicationSystemTestCase
  setup do
    travel_to Time.zone.local(2026, 10, 24, 12)
    @meeting = Meeting.create!(body_name: "Environmental Advisory Board", starts_at: Time.zone.local(2026, 9, 14, 18),
      detail_page_url: "https://example.com/archive-browser")
    Meeting.create!(body_name: "City Council", starts_at: Time.zone.local(2026, 8, 17, 18),
      detail_page_url: "https://example.com/archive-browser-older")
  end

  test "resident browses historical meetings in open mode" do
    assert_archive_journey
  end

  test "resident browses historical meetings in gated mode" do
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    assert_archive_journey
  end

  private

    def assert_archive_journey
      visit meetings_path
      click_link "Browse the meeting archive"
      assert_current_path meeting_archive_path
      click_link "September 2026", exact: true
      assert_selector "h1", text: /September 2026 Meetings/i
      page.driver.browser.manage.window.resize_to(320, 844)
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 320
      page.save_screenshot(Rails.root.join("tmp/screenshots/meeting-archive-mobile.png"))
      find(".meeting-archive-list a[href='#{meeting_path(@meeting)}']").click
      assert_current_path meeting_path(@meeting)
      assert_selector "h1", text: /Environmental Advisory Board/i
      page.go_back
      page.refresh
      assert_selector ".meeting-archive-list a[href='#{meeting_path(@meeting)}']"
      page.driver.browser.manage.window.resize_to(1280, 900)
      page.save_screenshot(Rails.root.join("tmp/screenshots/meeting-archive-desktop.png"))
      click_link "Older: August 2026"
      assert_selector "h1", text: /August 2026 Meetings/i
      click_link "Newer: September 2026"
      assert_selector "h1", text: /September 2026 Meetings/i
      click_link "All archive months"
      assert_current_path meeting_archive_path
      click_link "Upcoming and recent meetings"
      assert_current_path meetings_path
    end
end
