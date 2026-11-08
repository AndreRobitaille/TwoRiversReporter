require "application_system_test_case"
require_relative "../support/member_campaign_scenario"

class MemberCampaignJourneysTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  include MemberCampaignScenario

  test "saving a publisher correction updates the reader profile without a manual processing control" do
    setup_member_campaign
    analyze_member_campaign
    clear_enqueued_jobs
    admin = User.create!(email_address: "campaign-update-browser@example.test", admin: true, status: "active")
    admin.passkey_credentials.create!(external_id: "campaign-update-browser-key", public_key: "public-key", sign_count: 0)
    sign_in_by_email(admin)
    visit member_path(@jordan)
    assert_selector "#campaign-record .member-campaign-card", count: 2
    assert_selector "#campaign-record a", text: "Example Newspaper", count: 2, visible: :all
    visit admin_campaign_source_path(@source)
    click_link "Edit"
    fill_in "Publisher", with: "Corrected publisher"
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Metadata changes must reuse analysis" }) do
      perform_enqueued_jobs(only: ExtractCampaignSourceJob) do
        click_button "Save article"
        assert_selector ".flash", text: "Article saved."
      end
      visit member_path(@jordan)
      assert_selector "#campaign-record .member-campaign-card", count: 2
      assert_selector "#campaign-record a", text: "Corrected publisher", count: 2, visible: :all
      page.refresh
      find(".member-campaign-card > summary", match: :first).click
      assert_selector "#campaign-record a", text: "Corrected publisher", count: 1
    end
    assert_equal "Corrected publisher", @source.reload.current_version.publisher
    assert_equal 0, @source.current_version.extraction.attempts
    assert_equal 1, @calls.size
  end

  test "a reader follows a campaign statement to its publisher and loses reporting access after logout" do
    setup_member_campaign
    requested = Queue.new
    publisher = lambda do |env|
      requested << env.fetch("PATH_INFO")
      [ 200, { "content-type" => "text/html" }, [ "<h1>Synthetic candidate questionnaire</h1><p>Original article at the publisher.</p>" ] ]
    end
    source_server = Capybara::Server.new(publisher, host: "127.0.0.1").boot
    source_url = "http://127.0.0.1:#{source_server.port}/candidate-questionnaire"
    @source.update!(source_url: source_url, coverage: "selected_excerpts")
    analyze_member_campaign
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    sign_in_by_email(User.create!(email_address: "campaign-browser-reader@example.test", status: "active"))
    visit member_path(@jordan)
    page.driver.browser.manage.window.resize_to(390, 844)
    within "#campaign-record" do
      assert_selector ".member-campaign-card", count: 2
      assert_text "Repair neighborhood water lines."
      assert_text "Do not delay urgent repairs while waiting."
      assert_no_selector ".member-campaign-card[open]"
      assert_no_text "Selected excerpts"
      assert_no_link "Example Newspaper"
      find(".member-campaign-card > summary", match: :first).click
      assert_text "Selected excerpts"
      first("summary", text: "Read the question").click
      assert_text "Question 1: What would you prioritize?"
      all(".member-campaign-card > summary").last.click
      assert_selector ".member-campaign-card[open]", count: 1
      assert_no_text "Question 1: What would you prioritize?"
      find(".member-campaign-card > summary", match: :first).click
    end
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    find("#campaign-record").scroll_to(:top)
    page.save_screenshot(Rails.root.join("tmp/screenshots/member-campaign-mobile.png"))
    first("#campaign-record a", text: "Example Newspaper").click
    assert_current_path source_url, url: true
    assert_selector "h1", text: "Synthetic candidate questionnaire"
    assert_equal "/candidate-questionnaire", requested.pop
    page.go_back
    assert_selector "#campaign-record .member-campaign-card", count: 2
    page.refresh
    assert_no_selector ".member-campaign-card[open]"
    assert_text "Do not delay urgent repairs while waiting."
    find("button[aria-label='Toggle navigation']").click
    within ".site-nav" do
      find("a[href='#{public_session_path}'][data-turbo-method='delete']").click
    end
    assert_current_path root_path
    assert_nil authentication_cookie
    visit member_path(@jordan)
    assert_selector ".member-article-title", text: /Jordan Example/i
    assert_selector ".gate-card", count: 1
    assert_no_selector "#campaign-record"
    assert_not_includes page.html, "Repair neighborhood water lines."
    assert_not_includes page.html, source_url
    assert_equal 1, @calls.size
  end
end
