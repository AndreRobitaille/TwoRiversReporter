require "application_system_test_case"
require_relative "../support/vote_filter_scenario"

class MemberVoteFiltersJourneysTest < ApplicationSystemTestCase
  include VoteFilterScenario

  test "phone reader searches narrows pages opens a source and clears without losing the term" do
    setup_vote_filters
    page.driver.browser.manage.window.resize_to(390, 844)
    visit member_path(@member)
    click_link "All recorded votes"
    assert_selector ".member-vote-views [aria-current=page]", text: "All recorded votes"
    fill_in "Search votes", with: "Hamilton grant agreement"
    click_button "Search", exact: true
    assert_selector ".member-vote-filter-result", text: "26 matching votes"
    assert_equal "voting-record", URI.parse(page.current_url).fragment
    find(".member-vote-filter-options summary").click
    select "Riverfront Redevelopment", from: "Topic"
    select "Substantive", from: "Decision type"
    click_button "Apply filters"
    assert_selector ".member-vote-filter-result", text: "26 matching votes"
    assert_equal "voting-record", URI.parse(page.current_url).fragment
    within(".member-vote-pages") { click_link "2", exact: true }
    assert_selector ".member-recorded-votes .member-vote-row", count: 1
    assert_field "Search votes", with: "Hamilton grant agreement"
    assert_selector "select[name=topic] option:checked", text: "Riverfront Redevelopment"
    within("#recorded-vote-#{@grant_votes.first.id}") { click_link "Meeting and sources" }
    assert_current_path meeting_path(@meeting)
    page.go_back
    assert_selector ".member-vote-pages [aria-current=page]", text: "2"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    click_link "Clear search and filters"
    assert_no_selector ".member-vote-filter-result"
    assert_field "Council record", with: "2024-election"
    assert_selector ".member-vote-views [aria-current=page]", text: "All recorded votes"
    assert_selector ".member-recorded-votes .member-vote-row", count: 25
  end
end
