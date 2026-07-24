require "test_helper"

class ApplicationLayoutAuthStateTest < ActionDispatch::IntegrationTest
  test "signed out users see sign in and apply links" do
    get root_path

    assert_response :success
    assert_select "nav.site-nav a", text: "Sign in"
    assert_select "nav.site-nav a", text: "Apply"
    assert_select "nav.site-nav a", text: "Profile", count: 0
    assert_select "nav.site-nav a", text: "Security", count: 0
    assert_select "nav.site-nav a", text: "Admin", count: 0
    assert_select "nav.site-nav a", text: "Sign out", count: 0
  end

  test "signed-in users see profile and security links" do
    user = User.create!(email_address: "member@example.com", password: "password123", password_confirmation: "password123", status: "active")

    sign_in_via_magic_link(user)

    assert_select "nav.site-nav a", text: "Profile"
    assert_select "nav.site-nav a", text: "Security"
    assert_select "nav.site-nav a", text: "Sign out"
    assert_select "nav.site-nav a", text: "Sign in", count: 0
    assert_select "nav.site-nav a", text: "Apply", count: 0
    assert_select "nav.site-nav a", text: "Admin", count: 0
  end

  test "admins without passkeys do not see the admin link" do
    admin = User.create!(email_address: "admin-no-passkey@example.com", password: "password123", password_confirmation: "password123", status: "active", admin: true)

    sign_in_via_magic_link(admin)

    assert_select "nav.site-nav a", text: "Admin", count: 0
    assert_select "nav.site-nav a", text: "Security"
  end

  test "admins with passkeys see the admin link" do
    admin = User.create!(email_address: "admin@example.com", password: "password123", password_confirmation: "password123", status: "active", admin: true)
    admin.passkey_credentials.create!(external_id: "credential-1", public_key: "public-key", sign_count: 0)

    sign_in_via_magic_link(admin)

    assert_select "nav.site-nav a", text: "Admin"
  end

  test "users without passkeys see a dismissible reminder after magic link sign in" do
    user = User.create!(email_address: "prompt@example.com", password: "password123", password_confirmation: "password123", status: "active")

    sign_in_via_magic_link(user)

    assert_select ".passkey-prompt", text: /passkey/i
    assert_select ".passkey-prompt a[href='#{settings_security_path}']", text: "Open security settings"
    assert_select ".passkey-prompt a[href='#{settings_passkey_prompt_path}'][data-turbo-method='delete']", text: "Dismiss for a week"

    delete settings_passkey_prompt_path, headers: { "HTTP_REFERER" => root_url }

    assert_redirected_to root_url
    follow_redirect!

    assert_select ".passkey-prompt", count: 0
  end

  test "users with passkeys do not see the reminder" do
    user = User.create!(email_address: "passkey@example.com", password: "password123", password_confirmation: "password123", status: "active")
    user.passkey_credentials.create!(external_id: "credential-1", public_key: "public-key", sign_count: 0)

    sign_in_via_magic_link(user)

    assert_select ".passkey-prompt", count: 0
  end

  test "users with a future dismissal do not see the reminder" do
    user = User.create!(email_address: "dismissed@example.com", password: "password123", password_confirmation: "password123", status: "active", passkey_prompt_dismissed_until: 1.day.from_now)

    sign_in_via_magic_link(user)

    assert_select ".passkey-prompt", count: 0
  end

  private

    def sign_in_via_magic_link(user)
      magic_link = MagicLink.create_for!(user, purpose: "sign_in")

      post "/session/magic_link", params: { token: magic_link.raw_token }

      assert_redirected_to root_url
      follow_redirect!
    end
end
