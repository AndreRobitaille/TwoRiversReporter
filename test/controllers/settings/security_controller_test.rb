require "test_helper"

module Settings
  class SecurityControllerTest < ActionDispatch::IntegrationTest
    test "requires authentication" do
      get settings_security_path

      assert_redirected_to new_public_session_path
    end

    test "shows only the current users passkeys newest first" do
      user = User.create!(email_address: "security@example.com", status: "active")
      other = User.create!(email_address: "security-other@example.com", status: "active")

      older = user.passkey_credentials.create!(external_id: "older", public_key: "public", sign_count: 0, nickname: "Desk key", created_at: 2.days.ago)
      newest = user.passkey_credentials.create!(external_id: "newest", public_key: "public", sign_count: 0, created_at: 1.day.ago)
      other.passkey_credentials.create!(external_id: "theirs", public_key: "public", sign_count: 0, nickname: "Their key")

      sign_in_as(user)
      get settings_security_path

      assert_response :success
      assert_includes response.body, 'data-controller="passkey"'
      assert_includes response.body, 'data-passkey-target="status"'
      assert_includes response.body, "Add a passkey"
      assert_includes response.body, "Unnamed passkey"
      assert_includes response.body, "Desk key"
      assert_not_includes response.body, "Their key"
      assert_operator response.body.index("Unnamed passkey"), :<, response.body.index("Desk key")
      assert_includes response.body, passkey_path(newest)
      assert_includes response.body, passkey_path(older)
      assert_includes response.body, 'data-turbo-method="delete"'
    end

    test "shows only the current user's known contexts, most recently seen first" do
      user = User.create!(email_address: "known-contexts@example.com", status: "active")
      other = User.create!(email_address: "known-contexts-other@example.com", status: "active")

      KnownContext.create!(user: user, ip_prefix: "203.0.113.0/24", device_fingerprint: "chrome|macintosh", last_seen_at: 2.days.ago)
      KnownContext.create!(user: user, ip_prefix: "198.51.100.0/24", device_fingerprint: "firefox|windows", last_seen_at: 1.hour.ago)
      KnownContext.create!(user: other, ip_prefix: "192.0.2.0/24", device_fingerprint: "safari|iphone", last_seen_at: Time.current)

      sign_in_as(user)
      get settings_security_path

      assert_response :success
      assert_includes response.body, "198.51.100.0/24"
      assert_includes response.body, "Firefox on Windows"
      assert_includes response.body, "203.0.113.0/24"
      assert_includes response.body, "Chrome on Mac"
      assert_not_includes response.body, "192.0.2.0/24",
        "another member's network prefix must never appear on this page"
      assert_not_includes response.body, "Safari on iPhone",
        "another member's device must never appear on this page"
      assert_operator response.body.index("198.51.100.0/24"), :<, response.body.index("203.0.113.0/24"),
        "the most recently seen context should be listed first"
    end

    test "explains what is recorded and that it is forgotten after 90 days" do
      user = User.create!(email_address: "known-contexts-copy@example.com", status: "active")
      KnownContext.create!(user: user, ip_prefix: "203.0.113.0/24", device_fingerprint: "chrome|macintosh", last_seen_at: Time.current)

      sign_in_as(user)
      get settings_security_path

      assert_response :success
      assert_includes response.body, "90 days"
    end

    test "shows an empty state when the member has no recorded contexts" do
      user = User.create!(email_address: "known-contexts-empty@example.com", status: "active")

      sign_in_as(user)
      get settings_security_path

      assert_response :success
      assert_select ".empty-state"
    end

    test "requires authentication to dismiss the passkey prompt" do
      delete settings_passkey_prompt_path, headers: { "HTTP_REFERER" => root_url }

      assert_redirected_to new_public_session_path
    end

    test "dismisses only the signed in users passkey prompt" do
      user = User.create!(email_address: "prompt@example.com", status: "active")
      other = User.create!(email_address: "other@example.com", status: "active")

      travel_to Time.current do
        sign_in_as(user)
        delete settings_passkey_prompt_path, headers: { "HTTP_REFERER" => root_url }
      end

      assert_redirected_to root_url
      assert_predicate user.reload.passkey_prompt_dismissed_until, :future?
      assert_nil other.reload.passkey_prompt_dismissed_until
    end
  end
end
