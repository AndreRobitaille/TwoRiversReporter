require "application_system_test_case"
require_relative "../support/council_service_sources"

class MemberServicePeriodJourneysTest < ApplicationSystemTestCase
  include CouncilServiceSources

  test "resident reads sourced service dates on a phone and opens the retained record" do
    member = Member.create!(name: "Jordan Service Journey")
    source = service_source
    CouncilServicePeriod.record_starts!(period_key: "2024-election", source_version: source, page: 5,
      entries: [ { member_id: member.id, started_on: "2024-04-16" } ])
    page.driver.browser.manage.window.resize_to(390, 844)
    visit member_path(member)
    assert_selector ".member-service-period", text: "Term began April 16, 2024"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    page.save_screenshot(Rails.root.join("tmp/screenshots/member-service-period-mobile.png"))

    click_link "Start record, p. 5"
    assert_current_path %r{/rails/active_storage/disk/.+/synthetic-packet.pdf#page=5}, url: true
    token = URI.parse(page.current_url).path.split("/")[-2]
    assert_equal source.file.key, ActiveStorage.verifier.verified(token, purpose: "blob_key").fetch("key")
    page.go_back
    assert_current_path member_path(member)
    page.refresh
    assert_selector ".member-service-period", text: "Term began April 16, 2024"
  end
end
