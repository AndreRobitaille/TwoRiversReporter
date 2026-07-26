require "test_helper"
require "ostruct"

class PasskeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "passkey@example.com", status: "active")
    @other_user = User.create!(email_address: "other@example.com", status: "active")
    @inactive_user = User.create!(email_address: "inactive@example.com", status: "rejected")
  end

  test "unauthenticated users cannot request registration options" do
    post registration_options_passkeys_url

    assert_redirected_to new_public_session_url
  end

  test "authenticated users can request registration options and challenge is stored" do
    options = Struct.new(:challenge) do
      def as_json(*)
        { challenge: }
      end
    end.new("registration-challenge")
    headers = signed_session_headers(@user)
    WebAuthn::Credential.stub(:options_for_create, lambda { |**kwargs|
      assert_equal({ user: { id: @user.webauthn_id, name: @user.email_address, display_name: @user.email_address }, exclude: [] }, kwargs.except(:authenticator_selection))
      assert_equal({ resident_key: "required", user_verification: "required" }, kwargs[:authenticator_selection])
      options
    }) do
      post registration_options_passkeys_url, headers: headers
    end

    assert_response :success
    assert_equal options.to_json, response.body
  end

  test "registration stores verified credential and clears challenge" do
    credential = OpenStruct.new(id: "credential-123", public_key: "public-key", sign_count: 0)
    headers = signed_session_headers(@user)
    options = Struct.new(:challenge) do
      def as_json(*) = { challenge: }
    end.new("registration-challenge")
    WebAuthn::Credential.stub(:options_for_create, ->(*args, **kwargs) { options }) do
      WebAuthn::Credential.stub(:from_create, ->(*args, **kwargs) { credential }) do
      credential.define_singleton_method(:verify) do |challenge, user_verification:|
        @verified_args = [ challenge, user_verification ]
        true
      end
      post registration_options_passkeys_url, headers: headers
      post registration_passkeys_url, params: { credential: { raw: "value" } }, headers: headers
      assert_equal [ nil, true ], credential.instance_variable_get(:@verified_args)
      end
    end

    assert_response :success
    stored = PasskeyCredential.find_by!(external_id: "credential-123")
    assert_equal @user, stored.user
    assert_equal "public-key", stored.public_key
    assert_equal settings_security_url, response.parsed_body["redirect_to"]
  end

  test "registration returns unprocessable entity when ceremony parsing fails" do
    headers = signed_session_headers(@user)
    bad_credential = Object.new
    bad_credential.define_singleton_method(:verify) { |*| raise WebAuthn::Error, "bad ceremony" }
    bad_credential.define_singleton_method(:id) { "credential-123" }
    bad_credential.define_singleton_method(:public_key) { "public-key" }
    bad_credential.define_singleton_method(:sign_count) { 0 }
    WebAuthn::Credential.stub(:from_create, ->(*args, **kwargs) { bad_credential }) do
      post registration_passkeys_url, params: { credential: { raw: "value" } }, headers: headers
    end

    assert_response :unprocessable_entity
  end

  test "registration returns unprocessable entity for malformed credential payload" do
    headers = signed_session_headers(@user)

    post registration_passkeys_url, params: { credential: { malformed: true } }, headers: headers

    assert_response :unprocessable_entity
  end

  test "authentication_options stores challenge without login" do
    post authentication_options_passkeys_url

    assert_response :success
    assert_predicate response.body, :present?
  end

  test "authentication rejects unknown credentials" do
    WebAuthn::Credential.stub(:from_get, ->(*args, **kwargs) { OpenStruct.new(id: "missing", sign_count: 1) }) do
      post authentication_passkeys_url, params: { credential: { raw: "value" } }
    end

    assert_response :unauthorized
  end

  test "authentication returns unauthorized when ceremony parsing fails" do
    WebAuthn::Credential.stub(:from_get, ->(*args, **kwargs) { raise WebAuthn::Error, "bad ceremony" }) do
      post authentication_passkeys_url, params: { credential: { raw: "value" } }
    end

    assert_response :unauthorized
  end

  test "authentication returns unauthorized for malformed credential payload" do
    post authentication_passkeys_url, params: { credential: { malformed: true } }

    assert_response :unauthorized
  end

  test "authentication rejects inactive user" do
    credential = PasskeyCredential.create!(user: @inactive_user, external_id: "credential-123", public_key: "public-key", sign_count: 0)
    webauthn_credential = OpenStruct.new(id: credential.external_id, sign_count: 1)
    webauthn_credential.define_singleton_method(:verify) { |challenge, public_key:, sign_count:, user_verification:| true }
    WebAuthn::Credential.stub(:from_get, ->(*args, **kwargs) { webauthn_credential }) do
      post authentication_passkeys_url, params: { credential: { raw: "value" } }
    end

    assert_response :unauthorized
  end

  test "authenticated users can authenticate with verified credential" do
    credential = PasskeyCredential.create!(user: @user, external_id: "credential-123", public_key: "public-key", sign_count: 0)
    webauthn_credential = OpenStruct.new(id: credential.external_id, sign_count: 1)
    webauthn_credential.define_singleton_method(:verify) do |challenge, public_key:, sign_count:, user_verification:|
      @verified_args = [ challenge, public_key, sign_count, user_verification ]
      true
    end

    options = Struct.new(:challenge) do
      def as_json(*) = { challenge: }
    end.new("authentication-challenge")
    WebAuthn::Credential.stub(:options_for_get, ->(*args, **kwargs) { options }) do
      WebAuthn::Credential.stub(:from_get, ->(*args, **kwargs) { webauthn_credential }) do
        post authentication_options_passkeys_url
        post authentication_passkeys_url, params: { credential: { raw: "value" } }
        assert_equal [ "authentication-challenge", "public-key", 0, true ], webauthn_credential.instance_variable_get(:@verified_args)
      end
    end

    assert_response :success
  end

  test "update and destroy only affect current user's credentials" do
    mine = PasskeyCredential.create!(user: @user, external_id: "mine", public_key: "public-key", sign_count: 0)
    other = PasskeyCredential.create!(user: @other_user, external_id: "other", public_key: "public-key", sign_count: 0)

    headers = signed_session_headers(@user)
    patch passkey_url(mine), params: { passkey_credential: { nickname: "Renamed" } }, headers: headers
    assert_redirected_to settings_security_url
    assert_equal "Renamed", mine.reload.nickname

    patch passkey_url(other), params: { passkey_credential: { nickname: "Hacked" } }, headers: headers
    assert_response :not_found
    assert_nil other.reload.nickname

    delete passkey_url(mine), headers: headers
    assert_redirected_to settings_security_url
    assert_raises(ActiveRecord::RecordNotFound) { mine.reload }
    assert_predicate other.reload, :persisted?
  end

  test "a signed-in user can rename their own passkey" do
    mine = PasskeyCredential.create!(user: @user, external_id: "mine", public_key: "public-key", sign_count: 0)
    headers = signed_session_headers(@user)

    patch passkey_url(mine), params: { passkey_credential: { nickname: "Desk key" } }, headers: headers

    assert_redirected_to settings_security_url
    assert_equal "Desk key", mine.reload.nickname
  end

  test "the last usable admin cannot remove their final passkey" do
    admin = User.create!(email_address: "sole-passkey-admin@example.com", status: "active", admin: true)
    passkey = admin.passkey_credentials.create!(external_id: "sole-admin-passkey", public_key: "public-key", sign_count: 0)
    headers = signed_session_headers(admin)

    delete passkey_url(passkey), headers: headers

    assert_redirected_to settings_security_url
    assert_equal "At least one active admin with a passkey must remain.", flash[:alert]
    assert PasskeyCredential.exists?(passkey.id)
  end

  test "a user cannot rename another user's passkey" do
    theirs = PasskeyCredential.create!(user: @other_user, external_id: "theirs", public_key: "public-key", sign_count: 0, nickname: "Original")
    headers = signed_session_headers(@user)

    patch passkey_url(theirs), params: { passkey_credential: { nickname: "Hijacked" } }, headers: headers

    assert_response :not_found
    assert_equal "Original", theirs.reload.nickname
  end

  test "nickname is the only attribute a user can change through the passkey update endpoint" do
    mine = PasskeyCredential.create!(user: @user, external_id: "mine", public_key: "original-public-key", sign_count: 3)
    headers = signed_session_headers(@user)

    patch passkey_url(mine), params: {
      passkey_credential: {
        nickname: "My Yubikey",
        external_id: "attacker-controlled-id",
        public_key: "attacker-controlled-key",
        sign_count: 999,
        user_id: @other_user.id
      }
    }, headers: headers

    assert_redirected_to settings_security_url
    mine.reload
    assert_equal "My Yubikey", mine.nickname
    assert_equal "mine", mine.external_id
    assert_equal "original-public-key", mine.public_key
    assert_equal 3, mine.sign_count
    assert_equal @user.id, mine.user_id
  end

  private

    # Deliberately manual, not sign_in_as/sign_in_with_session:
    #
    # 1. sign_in_as creates a passkey credential for the user if they have
    #    none, and several tests here (e.g. the registration_options
    #    "exclude: []" assertion) depend on @user starting with zero
    #    passkeys.
    # 2. This helper hands back a raw "Cookie" header for the caller to pass
    #    explicitly per request (`headers: signed_session_headers(user)`).
    #    sign_in_with_session sets the cookie on the integration session's
    #    own persistent cookie jar instead — a different mechanism this
    #    file's call sites aren't using.
    #
    # The context stamp still has to match what an integration request sends
    # so a later context-mismatch gate does not intercept these requests.
    def signed_session_headers(user)
      session = Session.create!(
        user: user, user_agent: nil, ip_address: "127.0.0.1",
        ip_prefix: NetworkPrefix.for("127.0.0.1"),
        device_fingerprint: DeviceFingerprint.for(nil),
        reauthenticated_at: Time.current, last_seen_at: Time.current
      )
      req = ActionDispatch::TestRequest.create
      jar = ActionDispatch::Cookies::CookieJar.build(req, {})
      jar.signed[:session_id] = session.id
      { "Cookie" => jar.to_header }
    end
end
