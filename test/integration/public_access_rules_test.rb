require "test_helper"

class PublicAccessRulesTest < ActionDispatch::IntegrationTest
  test "root is public" do
    get root_url

    assert_response :success
  end

  test "about is public" do
    get about_url
    assert_response :success
  end

  test "sitemap is public" do
    get sitemap_url
    assert_response :success
  end

  test "non-exempt pages require login" do
    # Admin surfaces stay gated in both access modes; meetings (and the other
    # four public controllers) were restored to anonymous access by the
    # tiered-public-access plan — see docs/superpowers/plans/2026-07-24-tiered-public-access.md.
    get admin_root_url

    assert_redirected_to new_public_session_url
  end

  test "public application endpoints are still reachable" do
    get new_application_url
    assert_response :success
  end

  test "public passkey auth endpoints are still reachable" do
    post authentication_options_passkeys_url
    assert_response :success
  end

  test "signed-in users can access member pages" do
    user = User.create!(email_address: "member@example.com", status: "active")
    meeting = Meeting.create!(body_name: "City Council", starts_at: 1.day.ago, detail_page_url: "http://example.com/meeting")
    sign_in_as(user)
    get meeting_url(meeting)

    assert_response :success
  end

  test "settings security remains accessible to signed-in admins without passkeys" do
    admin = User.create!(email_address: "admin@example.com", admin: true, status: "active")
    session = Session.create!(
      user: admin, user_agent: nil, ip_address: "127.0.0.1",
      ip_prefix: NetworkPrefix.for("127.0.0.1"),
      device_fingerprint: DeviceFingerprint.for(nil),
      reauthenticated_at: Time.current, last_seen_at: Time.current
    )
    sign_in_with_session(session)
    get settings_security_url

    assert_response :success
  end
end
