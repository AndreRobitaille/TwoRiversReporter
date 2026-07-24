require "test_helper"

module Admin
  class MfaSetupControllerTest < ActionController::TestCase
    tests Admin::MfaSetupController

    test "inactive admin cannot enter mfa setup" do
      user = User.create!(email_address: "rejected-admin@example.com", password: "password123", password_confirmation: "password123", admin: true, status: "rejected")
      session[:pending_mfa_setup_user_id] = user.id

      get :show

      assert_redirected_to new_session_url
    end
  end
end
