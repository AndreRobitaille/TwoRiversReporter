require "application_system_test_case"

class PasskeyCeremonyJourneysTest < ApplicationSystemTestCase
  setup do
    @original_origins = WebAuthn.configuration.allowed_origins
    @original_rp_id = WebAuthn.configuration.rp_id
    WebAuthn.configure do |config|
      config.allowed_origins = [ "http://localhost:#{Capybara.current_session.server.port}" ]
      config.rp_id = "localhost"
    end
    options = Selenium::WebDriver::VirtualAuthenticatorOptions.new(protocol: :ctap2, transport: :internal,
      resident_key: true, user_verification: true, user_consenting: true, user_verified: true)
    @authenticator = page.driver.browser.add_virtual_authenticator(options)
    assert_equal true, page.evaluate_script("window.isSecureContext")
    assert_equal "localhost", URI.parse(current_url).host
  end

  teardown do
    @authenticator&.remove!
    WebAuthn.configure do |config|
      config.allowed_origins = @original_origins
      config.rp_id = @original_rp_id
    end
  end

  test "visible registration creates an owned credential that signs in and can be removed" do
    user = User.create!(email_address: "browser-passkey-resident@example.com", status: "active")
    sign_in_by_email(user)
    credential = register_passkey(user)
    signed_out_session = user.sessions.sole.id
    within ".site-nav" do
      click_link "Sign out", exact: true
    end
    assert_current_path root_path
    assert_not Session.exists?(signed_out_session)
    assert_nil authentication_cookie
    visit settings_profile_path
    assert_current_path new_public_session_path
    click_button "Sign in with a passkey"
    assert_current_path settings_profile_path
    assert_text user.email_address
    assert_equal user.id, user.sessions.sole.user_id
    assert_not_equal signed_out_session, user.sessions.sole.id
    assert_not_nil credential.reload.last_used_at
    assert_operator credential.sign_count, :>, 0

    visit settings_security_path
    assert_button "Add a passkey"
    accept_confirm { click_link "Remove", exact: true }
    assert_current_path settings_security_path
    assert_text "You haven't added any passkeys yet"
    assert_not PasskeyCredential.exists?(credential.id)
    assert_equal user.id, user.sessions.sole.user_id
    visit settings_profile_path
    assert_text user.email_address
  end

  test "stale proof is refreshed by a real passkey step-up and the next management task works" do
    user = User.create!(email_address: "browser-passkey-step-up@example.com", status: "active")
    sign_in_by_email(user)
    credential = register_passkey(user)
    current_session = user.sessions.sole
    current_session.update!(reauthenticated_at: 16.minutes.ago)
    visit settings_security_path
    assert_no_button "Add a passkey"
    assert_no_link "Remove", exact: true
    click_link "Confirm it's you", exact: true
    assert_current_path new_reauthentication_path
    assert_button "Confirm with a passkey"
    click_button "Confirm with a passkey"
    assert_current_path root_path
    visit settings_security_path
    assert_button "Add a passkey"
    assert_link "Remove", exact: true
    assert_predicate current_session.reload, :recently_reauthenticated?
    assert_equal current_session.id, user.sessions.sole.id
    assert_not_nil credential.reload.last_used_at

    # Proof may become stale after an allowed page was rendered. The real
    # DELETE must challenge, return to the referring GET page after step-up,
    # and leave the credential alone until the member repeats the action.
    current_session.update!(reauthenticated_at: 16.minutes.ago)
    accept_confirm { click_link "Remove", exact: true }
    assert_current_path new_reauthentication_path
    assert_predicate credential.reload, :persisted?
    click_button "Confirm with a passkey"
    assert_current_path settings_security_path
    assert_predicate credential.reload, :persisted?, "step-up must not replay the mutation as GET"
    assert_button "Add a passkey"
    assert_link "Remove", exact: true
    accept_confirm { click_link "Remove", exact: true }
    assert_current_path settings_security_path
    assert_not PasskeyCredential.exists?(credential.id)
    visit settings_security_path
    assert_button "Add a passkey"
    assert_no_link "Confirm it's you", exact: true
  end

  private

    def register_passkey(user)
      visit settings_security_path
      assert_button "Add a passkey"
      assert_empty user.passkey_credentials
      click_button "Add a passkey"
      assert_selector "section[data-controller='passkey'] .passkey-item"
      assert_equal 1, user.passkey_credentials.reload.count
      credential = user.passkey_credentials.reload.sole
      virtual = @authenticator.credentials.sole
      assert_equal user.id, credential.user_id
      assert_equal virtual.id, Base64.urlsafe_decode64(credential.external_id).bytes
      assert_equal "localhost", virtual.rp_id
      assert_predicate virtual, :resident_credential?
      assert_not_equal "fixture", credential.public_key
      assert_current_path settings_security_path
      credential
    end
end
