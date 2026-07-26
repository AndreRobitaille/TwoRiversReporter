require "test_helper"

module Admin
  class BaseControllerTest < ActionDispatch::IntegrationTest
    test "old admin password and otp routes no longer generate" do
      assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/admin/session/new", method: :get) }
      assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/admin/passwords/new", method: :get) }
      assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/admin/mfa_session/new", method: :get) }
      assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/admin/mfa_setup", method: :get) }
      assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/admin/recovery_codes", method: :get) }
      assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/admin/account_password/edit", method: :get) }
    end

    test "admin without passkey is redirected to security settings" do
      admin = User.create!(email_address: "admin@example.com", admin: true, status: "active")
      session = Session.create!(
        user: admin, user_agent: nil, ip_address: "127.0.0.1",
        ip_prefix: NetworkPrefix.for("127.0.0.1"),
        device_fingerprint: DeviceFingerprint.for(nil),
        reauthenticated_at: Time.current, last_seen_at: Time.current
      )
      sign_in_with_session(session)
      get admin_root_url

      assert_redirected_to settings_security_url
      assert_equal "Add a passkey before using admin tools.", flash[:alert]
    end

    test "admin with passkey can access admin pages" do
      admin = User.create!(email_address: "admin@example.com", admin: true, status: "active")
      admin.passkey_credentials.create!(external_id: "cred-123", public_key: "public-key", sign_count: 0)
      sign_in_as(admin)
      get admin_root_url

      assert_response :success
    end

    test "non-admin is denied admin access" do
      user = User.create!(email_address: "member@example.com", status: "active")
      session = Session.create!(
        user: user, user_agent: nil, ip_address: "127.0.0.1",
        ip_prefix: NetworkPrefix.for("127.0.0.1"),
        device_fingerprint: DeviceFingerprint.for(nil),
        reauthenticated_at: Time.current, last_seen_at: Time.current
      )
      sign_in_with_session(session)
      get admin_root_url

      assert_redirected_to root_url
      assert_equal "You do not have access to that section.", flash[:alert]
    end
  end
end
