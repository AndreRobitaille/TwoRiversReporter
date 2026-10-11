require "application_system_test_case"

class AuthenticationJourneysTest < ApplicationSystemTestCase
  test "member signs in by captured email and signs out from the public navigation" do
    user = User.create!(email_address: "browser-member@example.com", status: "active")
    sign_in_by_email(user)

    visit root_path
    within ".site-nav" do
      click_link "Sign out"
    end

    assert_logout_and_cookie_replay_denied(user)
  end

  test "eligible admin signs in by captured email and signs out from the admin sidebar" do
    user = User.create!(email_address: "browser-admin@example.com", status: "active", admin: true)
    # Admin eligibility fixture only: this is not a WebAuthn ceremony.
    user.passkey_credentials.create!(external_id: "browser-admin-key", public_key: "fixture", sign_count: 0)
    sign_in_by_email(user)

    click_link "Admin", exact: true
    assert_current_path admin_root_path
    within ".adm-sidebar__foot" do
      click_link "Sign Out"
    end

    assert_logout_and_cookie_replay_denied(user)
  end

  private

    def sign_in_by_email(user)
      super
      @authenticated_session_id = user.sessions.sole.id
      @authenticated_cookie = authentication_cookie
      assert_not_nil @authenticated_cookie
      assert @authenticated_cookie.fetch(:http_only)
    end

    def assert_logout_and_cookie_replay_denied(user)
      assert_current_path root_path
      assert_link "Sign in", exact: true
      assert_not Session.exists?(@authenticated_session_id), "logout must delete the formerly usable server session"
      assert_nil authentication_cookie, "logout must clear the authentication cookie"

      visit settings_profile_path
      assert_current_path new_public_session_path
      assert_no_text user.email_address

      page.driver.browser.manage.add_cookie(@authenticated_cookie)
      visit settings_profile_path
      assert_current_path new_public_session_path
      assert_no_text user.email_address
      assert_nil authentication_cookie
    end
end
