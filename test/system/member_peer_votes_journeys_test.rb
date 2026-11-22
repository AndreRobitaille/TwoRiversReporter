require "application_system_test_case"
require_relative "../support/peer_votes_setup"

class MemberPeerVotesJourneysTest < ApplicationSystemTestCase
  include PeerVotesSetup

  test "reader opens a comparison pages its decisions and inspects divided votes and exclusions on a phone" do
    setup_peer_votes
    26.times { |n| comparison_motion("Additional policy decision #{n}") }
    page.driver.browser.manage.window.resize_to(390, 844)
    visit member_path(@member)
    assert_no_selector "#peer-comparisons table"
    within "#peer-comparisons" do
      find("summary").click
      click_link "28 of 29"
    end
    assert_selector ".member-comparison-result", text: "Same vote on 28 of 29 decisions."
    assert_selector "[data-comparison-motion]", count: 25
    within(".member-vote-pages") { click_link "2", exact: true }
    assert_selector "[data-comparison-motion]", count: 4
    assert_selector "[data-comparison-motion='#{@agree.id}']", text: @agree.description
    click_link "Divided votes"
    assert_selector "[data-comparison-motion]", count: 1
    assert_selector ".member-comparison-result", text: "Same vote on 0 of 1 decisions."
    assert_selector ".member-vote-views [aria-current=page]", text: "Divided votes"
    click_link @split.description
    assert_current_path meeting_path(@comparison_meeting)
    page.go_back
    assert_selector "[data-comparison-motion='#{@split.id}']"
    assert_no_text "Vote inferred from attendance"
    find(".member-comparison-method summary").click
    assert_text "Vote inferred from attendance"
    assert_text "Jordan Attendance: Recused"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    click_link "Back to #{@member.name}'s record"
    assert_selector "select[name=term] option[selected][value='2024-election']", visible: :all
  end
end
