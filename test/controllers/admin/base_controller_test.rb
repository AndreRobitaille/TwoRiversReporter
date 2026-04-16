require "test_helper"

module Admin
  class BaseControllerTest < ActionDispatch::IntegrationTest
    test "development admin session without TOTP can access admin pages" do
      AdminMfaPolicy.stub :enforced?, false do
        admin = User.create!(email_address: "admin@example.com", password: "password", admin: true, totp_enabled: false)

        post session_url, params: { email_address: admin.email_address, password: "password" }
        get admin_root_url

        assert_response :success
      end
    end

    test "non-development admin session without TOTP redirects to setup" do
      AdminMfaPolicy.stub :enforced?, true do
        admin = User.create!(email_address: "admin@example.com", password: "password", admin: true, totp_enabled: false)

        post session_url, params: { email_address: admin.email_address, password: "password" }

        assert_redirected_to mfa_setup_url
      end
    end

    test "non-development enforced MFA blocks admin pages without TOTP" do
      admin = User.create!(email_address: "admin@example.com", password: "password", admin: true, totp_enabled: false)

      AdminMfaPolicy.stub :enforced?, false do
        post session_url, params: { email_address: admin.email_address, password: "password" }
        assert_response :redirect
      end

      AdminMfaPolicy.stub :enforced?, true do
        get admin_root_url

        assert_redirected_to new_session_url
      end
    end
  end
end
