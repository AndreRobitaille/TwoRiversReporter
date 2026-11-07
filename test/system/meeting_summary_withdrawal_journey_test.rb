require "application_system_test_case"
require_relative "../support/meeting_summary_withdrawal_scenario"

class MeetingSummaryWithdrawalJourneyTest < ApplicationSystemTestCase
  include MeetingSummaryWithdrawalScenario
  include ActiveJob::TestHelper

  setup do
    @previous_setting = SiteSetting.first
    @previous_mode = @previous_setting&.access_mode
    SiteSetting.instance.update!(access_mode: "open")
  end

  teardown do
    clean_summary_withdrawal_scenario
    @previous_setting ? @previous_setting.update!(access_mode: @previous_mode) : SiteSetting.first&.destroy!
  end

  test "resident follows official evidence after saved meeting analysis is withdrawn" do
    build_summary_withdrawal_scenario
    visit meeting_path(@meeting)
    assert_text CLAIM
    assert_text SECOND_CLAIM
    assert_selector "a[href='#{@document.source_url}']"
    without_summary_providers do
      download_summary_source("Synthetic revised source")
      visit meeting_path(@meeting)
      assert_text "Generated analysis was withdrawn because its supporting evidence changed."
      assert_no_text CLAIM
      assert_no_text SECOND_CLAIM
      assert_selector "a[href='#{@document.source_url}']"
      click_link "Back to Meetings"
      assert_current_path meetings_path
      visit meeting_path(@meeting)
      assert_text "Official sources remain available above."
      assert_no_text CLAIM
    end
  end
end
