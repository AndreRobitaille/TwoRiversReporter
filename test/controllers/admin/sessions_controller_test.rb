require "test_helper"

module Admin
  class SessionsControllerTest < ActionDispatch::IntegrationTest
    test "inactive admin cannot start admin session" do
      user = User.create!(email_address: "disabled-admin@example.com", password: "password123", password_confirmation: "password123", admin: true, status: "rejected")

      post session_path, params: { email_address: user.email_address, password: "password123" }

      assert_redirected_to new_session_url
    end

    test "disabled admin cannot start admin session" do
      user = User.create!(email_address: "disabled-admin@example.com", password: "password123", password_confirmation: "password123", admin: true, status: "active", disabled_at: Time.current)

      post session_path, params: { email_address: user.email_address, password: "password123" }

      assert_redirected_to new_session_url
    end

    test "active admin without passkey cannot bypass mfa flow" do
      user = User.create!(email_address: "active-admin@example.com", password: "password123", password_confirmation: "password123", admin: true, status: "active")

      post session_path, params: { email_address: user.email_address, password: "password123" }

      assert_redirected_to mfa_setup_url
      assert_equal user.id, session[:pending_mfa_setup_user_id]
    end
  end
end
