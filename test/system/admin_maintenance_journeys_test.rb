require "application_system_test_case"

class AdminMaintenanceJourneysTest < ApplicationSystemTestCase
  setup do
    @admin = User.create!(email_address: "browser-maintenance-admin@example.com", status: "active", admin: true)
    @admin.passkey_credentials.create!(external_id: "maintenance-eligibility", public_key: "fixture", sign_count: 0)
    sign_in_by_email(@admin)
    click_link "Admin", exact: true
  end

  test "topic inbox reaches the live canonical repair and reloads the same topic identity" do
    topic = Topic.create!(name: "browser maintenance canonical")
    topic_alias = topic.topic_aliases.create!(name: "browser maintenance replacement")
    canonical_name, alias_name = topic.name, topic_alias.name
    within "#admin-sidebar" do
      click_link "All Topics", exact: true
    end
    click_link canonical_name, exact: true
    assert_current_path admin_topic_path(topic)
    find("button.topic-decision-card__trigger", text: /This Topic Is Wrong/i).click
    click_button "Swap names", exact: true
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "canonical repair did not persist" unless topic.reload.name == alias_name
    end
    visit admin_topic_path(topic)
    assert_selector "h1", text: /#{Regexp.escape(alias_name)}/i
    assert_equal topic.id, topic_alias.reload.topic_id
    assert_equal canonical_name, topic_alias.name
    event = topic.topic_review_events.sole
    assert_equal "alias_flipped", event.action
    assert_equal @admin.id, event.user_id
    within "#admin-sidebar" do
      click_link "All Topics", exact: true
    end
    assert_selector "a[href='#{admin_topic_path(topic)}']", text: alias_name
  end

  test "blocklist entry is created and removed through its controls without removing another identity" do
    retained = TopicBlocklist.create!(name: "retained browser blocklist", reason: "Existing reason")
    within "#admin-sidebar" do
      click_link "Blocklist", exact: true
    end
    fill_in "Topic Name to Block", with: "browser boilerplate candidate"
    fill_in "Reason (Optional)", with: "Distinctive browser reason"
    click_button "Block Topic"
    assert_current_path admin_topic_blocklists_path
    assert_text "Distinctive browser reason"
    entry = TopicBlocklist.find_by!(name: "browser boilerplate candidate")
    assert_equal "Distinctive browser reason", entry.reason
    visit current_path
    within find("tr", text: entry.name) do
      accept_confirm { click_button "Remove" }
    end
    assert_selector ".flash--success"
    assert_not TopicBlocklist.exists?(entry.id)
    visit current_path
    assert_no_selector "tr", text: entry.name
    assert_selector "tr", text: retained.name
    assert_equal "Existing reason", retained.reload.reason
    fill_in "Topic Name to Block", with: retained.name
    click_button "Block Topic"
    assert_selector ".flash--danger", text: /Name.*taken/i
    assert_equal "Existing reason", retained.reload.reason
    assert_selector "tr", text: retained.name
  end

  test "redirect maintenance persists edits and the public old path follows the saved destination" do
    retained = Redirect.create!(source_path: "/retained-browser-path", destination: "/")
    within "#admin-sidebar" do
      click_link "Redirects", exact: true
    end
    click_link "New Redirect", exact: true
    fill_in "From (path)", with: "/overnight-browser-old"
    fill_in "To (path or URL)", with: "/about"
    fill_in "Note (optional)", with: "Distinctive browser redirect"
    click_button "Create Redirect"
    assert_current_path admin_redirects_path
    assert_text "Distinctive browser redirect"
    redirect = Redirect.find_by!(source_path: "/overnight-browser-old")
    assert_equal "/about", redirect.destination
    assert_equal 301, redirect.status_code
    visit redirect.source_path
    assert_current_path about_path
    assert_operator redirect.reload.hits, :>=, 1

    visit admin_redirects_path
    within find("tr", text: redirect.source_path) do
      click_link "Edit", exact: true
    end
    assert_field "From (path)", with: redirect.source_path
    fill_in "To (path or URL)", with: ""
    click_button "Update Redirect"
    assert_selector ".flash--danger", text: /Destination.*blank/i
    assert_equal "/about", redirect.reload.destination
    assert_equal 301, redirect.status_code
    visit edit_admin_redirect_path(redirect)
    assert_field "To (path or URL)", with: "/about"
    fill_in "To (path or URL)", with: "/meetings"
    select "302 — Temporary", from: "Type"
    click_button "Update Redirect"
    assert_current_path admin_redirects_path
    assert_equal "/meetings", redirect.reload.destination
    assert_equal 302, redirect.status_code
    visit redirect.source_path
    assert_current_path meetings_path

    visit admin_redirects_path
    within find("tr", text: redirect.source_path) do
      accept_confirm { click_button "Delete", exact: true }
    end
    assert_selector ".flash--success"
    assert_not Redirect.exists?(redirect.id)
    visit current_path
    assert_no_selector "tr", text: redirect.source_path
    assert_selector "tr", text: retained.source_path
    assert_equal "/", retained.reload.destination
  end
end
