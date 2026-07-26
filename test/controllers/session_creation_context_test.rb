require "test_helper"

class SessionCreationContextTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "signin@example.com", status: "active")
  end

  test "signing in with a magic link stamps the session context" do
    link = MagicLink.create_for!(@user, purpose: "sign_in")

    post magic_link_public_session_url, params: { token: link.raw_token }

    session = @user.sessions.sole
    assert_equal NetworkPrefix.for("127.0.0.1"), session.ip_prefix
    # DeviceFingerprint.for(nil) is always nil (see test/models/device_fingerprint_test.rb).
    # Minitest's assert_equal refuses a nil expected value ("Use assert_nil if
    # expecting nil"), so the equivalent nil check is spelled out directly.
    assert_nil session.device_fingerprint
  end

  test "signing in counts as a reauthentication" do
    link = MagicLink.create_for!(@user, purpose: "sign_in")

    post magic_link_public_session_url, params: { token: link.raw_token }

    session = @user.sessions.sole
    assert session.recently_reauthenticated?,
      "a fresh sign-in is itself proof of identity; without this, adding a first passkey would need a second email"
  end

  test "the stamped context matches the request that created it" do
    link = MagicLink.create_for!(@user, purpose: "sign_in")

    post magic_link_public_session_url, params: { token: link.raw_token }

    request_context = SessionContext.new(
      ip_prefix: NetworkPrefix.for("127.0.0.1"),
      device_fingerprint: DeviceFingerprint.for(nil)
    )

    assert request_context.matches?(@user.sessions.sole)
  end

  test "the raw ip and user agent are still recorded for display" do
    link = MagicLink.create_for!(@user, purpose: "sign_in")

    post magic_link_public_session_url, params: { token: link.raw_token }

    assert_equal "127.0.0.1", @user.sessions.sole.ip_address
  end
end
