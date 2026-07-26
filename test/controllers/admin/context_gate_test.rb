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

    # sign_in_as stamps reauthenticated_at, and the admin boundary honours a
    # recent step-up as well as a matching context — so every mismatch test here
    # has to age the step-up out of its window, or it is asserting nothing.
    test "an admin from a different network with no recent step-up is challenged" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24", reauthenticated_at: 16.minutes.ago)

      get admin_root_url

      assert_redirected_to new_reauthentication_url
    end

    test "an admin in a different browser with no recent step-up is challenged" do
      session = sign_in_as(@admin)
      session.update_columns(device_fingerprint: "safari|iphone", reauthenticated_at: 16.minutes.ago)

      get admin_root_url

      assert_redirected_to new_reauthentication_url
    end

    test "the challenge does not destroy the session" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24", reauthenticated_at: 16.minutes.ago)

      get admin_root_url

      assert Session.exists?(session.id),
        "a changed network must never sign anyone out; it only withholds sensitive surfaces"
    end

    test "the destination is remembered across the challenge" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24", reauthenticated_at: 16.minutes.ago)

      get admin_site_settings_url

      assert_redirected_to new_reauthentication_url
      assert_equal admin_site_settings_url, request.session[:return_to_after_authenticating]
    end

    test "a HEAD request remembers its own destination like GET" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24", reauthenticated_at: 16.minutes.ago)

      head admin_site_settings_url

      assert_redirected_to new_reauthentication_url
      assert_equal admin_site_settings_url, request.session[:return_to_after_authenticating]
    end

    test "stepping up restores access from the new network" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24", reauthenticated_at: 16.minutes.ago)

      get admin_root_url
      assert_redirected_to new_reauthentication_url

      session.reauthenticate!(SessionContext.new(
        ip_prefix: NetworkPrefix.for("127.0.0.1"),
        device_fingerprint: DeviceFingerprint.for(nil)
      ))

      get admin_root_url
      assert_response :success
    end

    # The lockout loop this grace exists to prevent: an egress that rotates its
    # address across /24 boundaries between requests (iCloud Private Relay,
    # carrier CGNAT, a proxy pool) drifts out of the recorded context again
    # immediately after a successful step-up. With a strict check here, every
    # admin page load would challenge again, forever.
    test "a step-up carries the admin through a context that drifts again" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24")

      assert_not_equal NetworkPrefix.for("127.0.0.1"), session.ip_prefix,
        "this test is only meaningful while the recorded context does not match the request"
      assert_predicate session, :recently_reauthenticated?,
        "and only meaningful while the step-up is still inside its window"

      get admin_root_url

      assert_response :success,
        "a step-up must survive address churn, or the admin area loops: challenge, step-up, challenge"
    end

    test "grace runs out with the step-up window" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24", reauthenticated_at: (Session::REAUTH_FRESHNESS + 1.minute).ago)

      get admin_root_url

      assert_redirected_to new_reauthentication_url,
        "the grace is a window, not a permanent exemption from the context check"
    end

    test "a non-admin is still denied before the context gate is reached" do
      member = User.create!(email_address: "gate-member@example.com", status: "active")
      session = sign_in_as(member)
      session.update_columns(ip_prefix: "198.51.100.0/24", reauthenticated_at: 16.minutes.ago)

      get admin_root_url

      assert_redirected_to root_url,
        "the admin check must run first, or a mismatched context would tell a stranger that admin exists"
    end
  end
end
