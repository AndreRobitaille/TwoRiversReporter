require "test_helper"

module Admin
  class MfaSessionsControllerTest < ActionController::TestCase
    tests Admin::MfaSessionsController

    test "inactive admin cannot complete mfa session" do
      user = User.create!(email_address: "pending-admin@example.com", password: "password123", password_confirmation: "password123", admin: true, status: "pending", totp_enabled: true, totp_secret: "SECRETSECRETSECRETSECRETSECRETSECRET")
      session[:pending_mfa_user_id] = user.id

      get :new

      assert_redirected_to new_session_url
    end

    test "disabled admin cannot complete mfa session" do
      user = User.create!(email_address: "disabled-admin@example.com", password: "password123", password_confirmation: "password123", admin: true, status: "active", disabled_at: Time.current, totp_enabled: true, totp_secret: "SECRETSECRETSECRETSECRETSECRETSECRET")
      session[:pending_mfa_user_id] = user.id

      get :new

      assert_redirected_to new_session_url
    end
  end
end
