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

      get settings_security_path, headers: signed_session_headers(user)

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

    test "requires authentication to dismiss the passkey prompt" do
      delete settings_passkey_prompt_path, headers: { "HTTP_REFERER" => root_url }

      assert_redirected_to new_public_session_path
    end

    test "dismisses only the signed in users passkey prompt" do
      user = User.create!(email_address: "prompt@example.com", status: "active")
      other = User.create!(email_address: "other@example.com", status: "active")

      travel_to Time.current do
        delete settings_passkey_prompt_path, headers: signed_session_headers(user).merge("HTTP_REFERER" => root_url)
      end

      assert_redirected_to root_url
      assert_predicate user.reload.passkey_prompt_dismissed_until, :future?
      assert_nil other.reload.passkey_prompt_dismissed_until
    end

    private

      def signed_session_headers(user)
        session = Session.create!(user: user, last_seen_at: Time.current)
        req = ActionDispatch::TestRequest.create
        jar = ActionDispatch::Cookies::CookieJar.build(req, {})
        jar.signed[:session_id] = session.id
        { "Cookie" => jar.to_header }
      end
  end
end
