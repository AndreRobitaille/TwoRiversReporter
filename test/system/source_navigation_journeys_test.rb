require "application_system_test_case"

class SourceNavigationJourneysTest < ApplicationSystemTestCase
  test "approved reader opens the actual source destination before losing source controls on logout" do
    # Only the external publisher is a synthetic Rack fixture. The app's link,
    # new browser window, request and source response are real and offline.
    requested = Queue.new
    publisher = lambda do |env|
      requested << env.fetch("PATH_INFO")
      [ 200, { "content-type" => "text/html" }, [ "<h1>Synthetic official meeting record</h1><p>Source identity alpha</p>" ] ]
    end
    source_server = Capybara::Server.new(publisher, host: "127.0.0.1").boot
    source_url = "http://127.0.0.1:#{source_server.port}/official-meeting-alpha"
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    meeting = Meeting.create!(body_name: "Source Browser Commission", starts_at: 2.days.ago, detail_page_url: source_url)
    sign_in_by_email(User.create!(email_address: "source-browser-reader@example.com", status: "active"))
    visit meeting_path(meeting)
    assert_selector ".meeting-article-docs a[href='#{source_url}']", text: /City Website/i
    source_window = window_opened_by { find(".meeting-article-docs a[href='#{source_url}']").click }
    within_window(source_window) do
      assert_current_path source_url, url: true
      assert_selector "h1", text: "Synthetic official meeting record"
      assert_text "Source identity alpha"
    end
    source_window.close
    assert_equal "/official-meeting-alpha", requested.pop
    within ".site-nav" do
      find("a[href='#{public_session_path}'][data-turbo-method='delete']").click
    end
    assert_current_path root_path
    assert_nil authentication_cookie
    visit meeting_path(meeting)
    assert_current_path meeting_path(meeting)
    assert_no_selector ".meeting-article-docs a[href]"
    assert_selector ".meeting-doc-link--disabled", text: /City Website/i
    assert_not_includes page.html, source_url
  end
end
