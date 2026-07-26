require "test_helper"

module Admin
  class ContextGateTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "gate-admin@example.com", admin: true, status: "active")
    end

    test "an admin on the recorded network and browser is not challenged" do
      sign_in_as(@admin)

      get admin_root_url

      assert_response :success
    end

    test "an admin from a different network is challenged" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24")

      get admin_root_url

      assert_redirected_to new_reauthentication_url
    end

    test "an admin in a different browser is challenged" do
      session = sign_in_as(@admin)
      session.update_columns(device_fingerprint: "safari|iphone")

      get admin_root_url

      assert_redirected_to new_reauthentication_url
    end

    test "the challenge does not destroy the session" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24")

      get admin_root_url

      assert Session.exists?(session.id),
        "a changed network must never sign anyone out; it only withholds sensitive surfaces"
    end

    test "the destination is remembered across the challenge" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24")

      get admin_site_settings_url

      assert_redirected_to new_reauthentication_url
      assert_equal admin_site_settings_url, request.session[:return_to_after_authenticating]
    end

    test "stepping up restores access from the new network" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24")

      get admin_root_url
      assert_redirected_to new_reauthentication_url

      session.reauthenticate!(SessionContext.new(
        ip_prefix: NetworkPrefix.for("127.0.0.1"),
        device_fingerprint: DeviceFingerprint.for(nil)
      ))

      get admin_root_url
      assert_response :success
    end

    test "a non-admin is still denied before the context gate is reached" do
      member = User.create!(email_address: "gate-member@example.com", status: "active")
      session = sign_in_as(member)
      session.update_columns(ip_prefix: "198.51.100.0/24")

      get admin_root_url

      assert_redirected_to root_url,
        "the admin check must run first, or a mismatched context would tell a stranger that admin exists"
    end
  end
end
