require "test_helper"

# Each gated action is asserted individually rather than once per controller.
# A previous review on this codebase found a guard whose real protection lived
# in a different method than the one under test, which a controller-level
# assertion would not have caught.
class FreshReauthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "fresh-admin@example.com", admin: true, status: "active")
    @other_admin = User.create!(email_address: "second-admin@example.com", admin: true, status: "active")
    @member = User.create!(email_address: "fresh-member@example.com", status: "active")
  end

  test "deleting a user requires a fresh reauthentication" do
    session = sign_in_as(@admin)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    assert_no_difference -> { User.count } do
      delete user_url(@member)
    end

    assert_redirected_to new_reauthentication_url
  end

  test "deleting a user succeeds with a fresh reauthentication" do
    sign_in_as(@admin)

    assert_difference -> { User.count }, -1 do
      delete user_url(@member)
    end
  end

  test "deleting an application requires a fresh reauthentication" do
    application = @member.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
    session = sign_in_as(@admin)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    assert_no_difference -> { MembershipApplication.count } do
      delete admin_membership_application_url(application)
    end

    assert_redirected_to new_reauthentication_url
  end

  test "creating an admin requires a fresh reauthentication" do
    session = sign_in_as(@admin)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    assert_no_difference -> { User.count } do
      post users_url, params: { user: { email_address: "new-admin@example.com" } }
    end

    assert_redirected_to new_reauthentication_url
  end

  test "granting admin requires a fresh reauthentication" do
    session = sign_in_as(@admin)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    patch toggle_admin_user_url(@member)

    assert_redirected_to new_reauthentication_url
    assert_not @member.reload.admin?
  end

  test "disabling a user requires a fresh reauthentication" do
    session = sign_in_as(@admin)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    patch disable_user_url(@member)

    assert_redirected_to new_reauthentication_url
    assert_predicate @member.reload.disabled_at, :blank?
  end

  test "approving an application does not require a fresh reauthentication" do
    @member.update!(status: "pending", disabled_at: Time.current)
    @member.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
    session = sign_in_as(@admin)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    patch approve_user_url(@member)

    assert_equal "active", @member.reload.status,
      "routine membership review is covered by the admin context gate; putting it behind a passkey tap taxes the most common admin task"
  end

  test "removing a passkey requires a fresh reauthentication" do
    session = sign_in_as(@member)
    credential = @member.passkey_credentials.sole
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    assert_no_difference -> { PasskeyCredential.count } do
      delete passkey_url(credential)
    end

    assert_redirected_to new_reauthentication_url
  end

  test "removing a passkey succeeds with a fresh reauthentication" do
    sign_in_as(@member)
    credential = @member.passkey_credentials.sole

    assert_difference -> { PasskeyCredential.count }, -1 do
      delete passkey_url(credential)
    end
  end

  test "the passkey registration endpoints answer JSON with a status, not a redirect" do
    session = sign_in_as(@member)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    post registration_options_passkeys_url(format: :json)

    assert_response :forbidden,
      "a 302 to an HTML page would be read by passkey_controller.js as a malformed options response"
  end

  test "a member who just signed in can add a first passkey without a second email" do
    fresh_member = User.create!(email_address: "brand-new@example.com", status: "active")
    link = MagicLink.create_for!(fresh_member, purpose: "sign_in")

    post magic_link_public_session_url, params: { token: link.raw_token }
    post registration_options_passkeys_url(format: :json)

    assert_response :success
  end

  test "the security page hides passkey controls when the session is stale" do
    session = sign_in_as(@member)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    get settings_security_url

    assert_response :success
    assert_select "button[data-action='passkey#register']", count: 0
    assert_select "a[href=?]", new_reauthentication_path
  end

  test "the security page shows passkey controls when the session is fresh" do
    sign_in_as(@member)

    get settings_security_url

    assert_select "button[data-action='passkey#register']", count: 1
  end
end
