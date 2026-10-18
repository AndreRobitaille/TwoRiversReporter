require "application_system_test_case"

class TopicContextJourneysTest < ApplicationSystemTestCase
  test "admin saves nonblank resident context through the topic form and reloads its provenance" do
    admin = User.create!(email_address: "browser-context-editor@example.com", status: "active", admin: true)
    admin.passkey_credentials.create!(external_id: "context-admin-eligibility", public_key: "fixture", sign_count: 0)
    topic = Topic.create!(name: "browser context water project", description: "Existing context description")
    identity = topic.attributes.slice("id", "name", "slug", "description")
    sign_in_by_email(admin)
    click_link "Admin", exact: true
    within "#admin-sidebar" do
      click_link "All Topics", exact: true
    end
    find("a[href='#{admin_topic_path(topic)}']").click
    assert_current_path admin_topic_path(topic)
    assert_nil topic.source_notes

    find("summary", text: /Edit Details/i).click
    fill_in "Resident context", with: "Distinctive browser resident observation"
    select "Admin observation", from: "Context source"
    before_save = Time.current.change(usec: 0)
    click_button "Save", exact: true
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "resident context was not persisted" unless topic.reload.source_notes == "Distinctive browser resident observation"
    end

    visit current_path
    find("summary", text: /Edit Details/i).click
    assert_field "Resident context", with: "Distinctive browser resident observation"
    assert_equal admin.email_address, topic.reload.added_by
    assert_operator Time.parse(topic.added_at), :>=, before_save
    assert_operator Time.parse(topic.added_at), :<=, Time.current
    assert_equal "admin_observation", topic.source_type
    assert_equal identity, topic.attributes.slice(*identity.keys)

    fill_in "Resident context", with: ""
    click_button "Save", exact: true
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "context was not cleared" unless topic.reload.source_notes == ""
    end
    visit current_path
    find("summary", text: /Edit Details/i).click
    assert_field "Resident context", with: ""
    assert_nil topic.reload.added_by
    assert_nil topic.added_at
    assert_equal identity, topic.attributes.slice(*identity.keys)
  end
end
