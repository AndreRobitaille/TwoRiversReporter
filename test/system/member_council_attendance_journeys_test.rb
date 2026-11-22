require "application_system_test_case"
require_relative "../support/council_attendance_setup"

class MemberCouncilAttendanceJourneysTest < ApplicationSystemTestCase
  include CouncilAttendanceSetup

  test "resident expands attendance on a phone opens a meeting and returns to updated counts" do
    setup_council_attendance
    meeting = council_meeting("2024-04-16", attendance: "present")
    missing = council_meeting("2024-04-17")
    page.driver.browser.manage.window.resize_to(390, 844)
    visit member_path(@member)
    within "#council-attendance" do
      assert_selector "[data-attendance-status='present'] dd", text: "1", exact_text: true
      assert_selector "[data-attendance-status='unknown'] dd", text: "1", exact_text: true
      assert_no_selector "li"
      find("summary").click
      assert_selector "li", count: 2
      assert_selector "li", text: /Apr 17, 2024 · Regular\s+Not recorded/
      page.save_screenshot(Rails.root.join("tmp/screenshots/council-attendance-mobile.png"))
      click_link "Apr 16, 2024 · Regular"
    end
    assert_current_path meeting_path(meeting)
    assert_selector "h1", text: /City Council/i
    page.go_back
    assert_current_path member_path(@member)
    missing.meeting_attendances.create!(member: @member, status: "excused", attendee_type: "voting_member")
    page.refresh
    assert_selector "#council-attendance [data-attendance-status='excused'] dd", text: "1", exact_text: true
    assert_selector "#council-attendance [data-attendance-status='unknown'] dd", text: "0", exact_text: true
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
  end
end
