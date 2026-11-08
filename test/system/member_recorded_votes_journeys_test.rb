require "application_system_test_case"

class MemberRecordedVotesJourneysTest < ApplicationSystemTestCase
  test "reader switches views paginates and opens a meeting source on a phone" do
    publisher = ->(_env) { [ 200, { "content-type" => "text/html" }, [ "<h1>Synthetic Council minutes</h1><p>Negotiations authorized; agreement returns later.</p>" ] ] }
    source_server = Capybara::Server.new(publisher, host: "127.0.0.1").boot
    source_url = "http://127.0.0.1:#{source_server.port}/minutes"
    member = Member.create!(name: "Morgan Record")
    meeting = Meeting.create!(body_name: "City Council", starts_at: Time.zone.local(2025, 5, 30, 11, 45), detail_page_url: source_url)
    motion = meeting.motions.create!(description: "Authorize manager negotiations; return the proposed agreement for later Council action", outcome: "passed")
    vote = motion.votes.create!(member: member, value: "yes")
    25.times do |index|
      meeting.motions.create!(description: "Approve minutes for synthetic session #{index}", outcome: "passed")
        .votes.create!(member: member, value: "yes")
    end
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    sign_in_by_email(User.create!(email_address: "recorded-votes-browser@example.com", status: "active"))

    visit member_path(member)
    click_link "All recorded votes"
    assert_selector ".member-vote-views a[aria-current='page']", text: "All recorded votes"
    assert_selector ".member-recorded-votes .member-vote-row", count: 25
    assert_text "Approve minutes for synthetic session 24"
    assert_text "may omit meetings or votes"
    assert_operator page.evaluate_script("document.querySelector('#voting-record').getBoundingClientRect().top"), :>=,
      page.evaluate_script("document.querySelector('.site-header').getBoundingClientRect().bottom")
    page.save_screenshot(Rails.root.join("tmp/screenshots/recorded-votes-desktop.png"))

    page.driver.browser.manage.window.resize_to(390, 844)
    click_link "Older votes"
    assert_selector ".member-recorded-votes .member-vote-row", count: 1
    assert_selector "#recorded-vote-#{vote.id}", text: motion.description
    assert_selector ".member-vote-views a[aria-current='page']", text: "All recorded votes"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    page.save_screenshot(Rails.root.join("tmp/screenshots/recorded-votes-mobile.png"))
    click_link "Meeting and sources"
    assert_current_path meeting_path(meeting)
    source_window = window_opened_by { find(".meeting-article-docs a[href='#{source_url}']").click }
    within_window(source_window) do
      assert_selector "h1", text: "Synthetic Council minutes"
      assert_text "Negotiations authorized; agreement returns later."
    end
    source_window.close
    page.go_back
    assert_selector "#recorded-vote-#{vote.id}", text: motion.description
    click_link "Newer votes"
    assert_selector ".member-recorded-votes .member-vote-row", count: 25
    click_link "Featured votes"
    assert_no_selector ".member-recorded-votes"
    assert_selector ".member-vote-views a[aria-current='page']", text: "Featured votes"

    page.driver.browser.manage.window.resize_to(1280, 900)
    within ".site-nav" do
      find("a[href='#{public_session_path}'][data-turbo-method='delete']").click
    end
    assert_current_path root_path
    visit member_path(member, votes: "all", page: 2)
    assert_text /Sign in to keep reading/i
    assert_not_includes page.html, motion.description
    assert_no_selector ".member-recorded-votes, .member-vote-pages"
  end
end
