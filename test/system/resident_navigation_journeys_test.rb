require "application_system_test_case"

class ResidentNavigationJourneysTest < ApplicationSystemTestCase
  setup do
    page.driver.browser.manage.window.resize_to(1280, 900)
    @topic = Topic.create!(name: "browser water improvement", status: "approved",
      lifecycle_status: "active", resident_impact_score: 5, last_activity_at: 1.day.ago)
    @meeting = Meeting.create!(body_name: "City Council Meeting", starts_at: 5.days.from_now,
      detail_page_url: "https://example.com/browser-council")
    item = @meeting.agenda_items.create!(title: "Water improvement proposal")
    AgendaItemTopic.create!(agenda_item: item, topic: @topic)
  end

  test "anonymous resident follows homepage topic and meeting links in open mode" do
    assert_resident_navigation
  end

  test "the mobile Council roster starts with a closed election guide and election links open it" do
    travel_to Date.new(2027, 2, 1) do
      council = Committee.find_or_create_by!(name: "City Council")
      member = Member.create!(name: "Mark Bittner")
      CommitteeMembership.create!(committee: council, member: member, role: "member", source: "admin_manual")
      profile = member_path(member)

      page.driver.browser.manage.window.resize_to(390, 844)
      visit committee_path(council.slug)
      assert_selector "#current-members a[href='#{profile}']"
      assert_selector "#spring-election details:not([open]) > summary", text: "Spring 2027 Council election"
      assert_operator find("#spring-election").native.rect.y, :<, find("#current-members").native.rect.y
      assert_no_selector "#spring-election .election-timeline"
      find("#spring-election summary").send_keys(:enter)
      assert_selector "#spring-election a[href='#{profile}']", text: member.name
      find("#spring-election summary").click
      assert_no_selector "#spring-election .election-timeline"

      visit root_path
      click_link "Spring 2027 City Council election"
      assert_selector "#spring-election a[href='#{profile}']"
      find("#spring-election a[href='#{profile}']").click
      within ".council-work" do
        assert_field "Find a vote or meeting"
        find("summary").send_keys(:enter)
        assert_no_field "Find a vote or meeting"
        find("summary").send_keys(:enter)
        assert_field "Find a vote or meeting"
      end
      click_link "Election dates"
      assert_selector "#spring-election a[href='#{profile}']"

      page.driver.browser.manage.window.resize_to(1280, 900)
      visit committee_path(council.slug)
      assert_selector "#spring-election h2", text: "Spring 2027 Council election"
      assert_selector "#spring-election a[href='#{profile}']"
      assert_no_selector "#spring-election summary"
    end
  end

  test "anonymous resident follows homepage topic and meeting links in gated mode" do
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    assert_resident_navigation
  end

  test "approved member follows homepage topic and meeting links in gated mode" do
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    sign_in_by_email(User.create!(email_address: "navigation-member@example.com", status: "active"))
    assert_resident_navigation
  end

  test "member follows a communications topic without an agenda detail card" do
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    @topic.update!(name: "city administrator conduct and council oversight")
    MeetingSummary.create!(meeting: @meeting, summary_type: "agenda_preview", generation_data: {
      "headline" => "Council will hear resident concerns",
      "public_input" => [], "item_details" => []
    })
    sign_in_by_email(User.create!(email_address: "communications-reader@example.com", status: "active"))

    visit meeting_path(@meeting)
    page.driver.browser.manage.window.resize_to(390, 844)
    assert_selector ".meeting-related-topics a[href='#{topic_path(@topic)}']", count: 1
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    page.execute_script("document.querySelector('.meeting-related-topics').scrollIntoView({block: 'center'})")
    page.save_screenshot(Rails.root.join("tmp/screenshots/meeting-topic-fallback-mobile.png"))
    find(".meeting-related-topics a[href='#{topic_path(@topic)}']").click
    assert_current_path topic_path(@topic)
    assert_selector "h1", text: /#{Regexp.escape(@topic.name)}/i
    page.go_back
    assert_current_path meeting_path(@meeting)
    page.refresh
    assert_selector ".meeting-related-topics a[href='#{topic_path(@topic)}']", count: 1
    page.driver.browser.manage.window.resize_to(1280, 900)
    page.save_screenshot(Rails.root.join("tmp/screenshots/meeting-topic-fallback-desktop.png"))
  end

  test "member follows a voter profile from a meeting and topic and returns to the record" do
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    @meeting.update!(starts_at: 1.day.ago)
    item = @meeting.agenda_items.first
    member = Member.create!(name: "Jordan Navigation")
    motion = @meeting.motions.create!(agenda_item: item, description: "Approve water improvements", outcome: "passed")
    motion.votes.create!(member: member, value: "yes")
    @meeting.meeting_summaries.create!(summary_type: "minutes_recap", generation_data: {
      "headline" => "Water improvements approved", "item_details" => [
        { "agenda_item_id" => item.id, "agenda_item_title" => item.title, "summary" => "Approved the improvements." }
      ]
    })
    sign_in_by_email(User.create!(email_address: "voter-navigation@example.com", status: "active"))

    visit meeting_path(@meeting)
    page.driver.browser.manage.window.resize_to(390, 844)
    find(".meeting-vote-breakdown summary").click
    within ".meeting-vote-list" do
      click_link member.name
    end
    assert_current_path member_path(member)
    assert_selector "h1", text: /Jordan Navigation/i
    find(".member-topic-name a[href='#{topic_path(@topic)}']").click
    assert_current_path topic_path(@topic)
    within ".votes-grid" do
      click_link member.name
    end
    assert_current_path member_path(member)
    find(".member-topic-votes a[href='#{meeting_path(@meeting)}']").click
    assert_current_path meeting_path(@meeting)
    page.refresh
    find(".meeting-vote-breakdown summary").click
    assert_selector ".meeting-vote-list a[href='#{member_path(member)}']", text: member.name
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    page.execute_script("document.querySelector('.meeting-vote-breakdown').scrollIntoView({block: 'center'})")
    page.save_screenshot(Rails.root.join("tmp/screenshots/voter-profile-link-mobile.png"))
  end

  private

    def assert_resident_navigation
      visit root_path
      find("a.top-story[href='#{topic_path(@topic)}']").click
      assert_current_path topic_path(@topic)
      assert_selector "h1", text: /#{Regexp.escape(@topic.name)}/i

      visit root_path
      find("a.nextup-card[href='#{meeting_path(@meeting)}']").click
      assert_current_path meeting_path(@meeting)
      assert_selector "h1", text: /Council/i

      within ".site-nav" do
        click_link "Topics", exact: true
      end
      assert_current_path topics_path
      assert_selector "a[href='#{topic_path(@topic)}']", text: /#{Regexp.escape(@topic.name)}/i

      within ".site-nav" do
        click_link "Meetings", exact: true
      end
      assert_current_path meetings_path
      assert_selector "a[href='#{meeting_path(@meeting)}']"
    end
end
