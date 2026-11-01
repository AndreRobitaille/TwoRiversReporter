require "test_helper"
require "webauthn/fake_client"

class PasskeySignatureErrorsTest < ActionDispatch::IntegrationTest
  MALFORMED_SIGNATURES = {
    invalid_der: "not an ECDSA signature",
    truncated_der: "\x30\x06\x02\x01\x01"
  }.freeze

  setup do
    @user = User.create!(email_address: "signature-errors@example.com", status: "active")
    @client = WebAuthn::FakeClient.new(WebAuthn.configuration.allowed_origins.first)
    options = WebAuthn::Credential.options_for_get
    registration = WebAuthn::Credential.from_create(
      @client.create(challenge: options.challenge, user_verified: true)
    )
    registration.verify(options.challenge, user_verification: true)
    @credential = @user.passkey_credentials.create!(
      external_id: registration.id, public_key: registration.public_key, sign_count: registration.sign_count
    )
  end

  MALFORMED_SIGNATURES.each do |name, signature|
    test "sign in rejects #{name} without granting access then accepts a fresh valid assertion" do
      sign_in_with_passkey
      get settings_profile_path
      assert_response :success
      assert_includes response.body, @user.email_address
      delete public_session_path
      assert_empty @user.sessions.reload

      valid = assertion_for(authentication_options_passkeys_path)
      before = @credential.reload.attributes
      post authentication_passkeys_path, params: { credential: with_signature(valid, signature) }, as: :json

      assert_response :unauthorized
      assert_equal before, @credential.reload.attributes
      assert_empty @user.sessions.reload
      get settings_profile_path
      assert_redirected_to new_public_session_path

      # A valid signature cannot reuse the challenge consumed by the failure.
      post authentication_passkeys_path, params: { credential: valid }, as: :json
      assert_response :unauthorized
      assert_equal before, @credential.reload.attributes
      assert_empty @user.sessions.reload

      sign_in_with_passkey
      get settings_profile_path
      assert_response :success
      assert_includes response.body, @user.email_address
      assert_equal @user.id, @user.sessions.reload.sole.user_id
      assert_operator @credential.reload.sign_count, :>, before.fetch("sign_count")
    end

    test "step up rejects #{name} without refreshing proof then accepts a fresh valid assertion" do
      sign_in_with_passkey
      session = @user.sessions.reload.sole
      session.update!(reauthenticated_at: 16.minutes.ago)
      step_up_with_passkey
      assert_predicate session.reload, :recently_reauthenticated?
      post registration_options_passkeys_path, as: :json
      assert_response :success

      session.update!(reauthenticated_at: 16.minutes.ago)
      valid = assertion_for(passkey_options_reauthentication_path)
      before_session = session.reload.attributes
      before_credential = @credential.reload.attributes
      post passkey_reauthentication_path, params: { credential: with_signature(valid, signature) }, as: :json

      assert_response :unauthorized
      assert_equal before_credential, @credential.reload.attributes
      assert_equal before_session, session.reload.attributes
      assert_equal session.id, @user.sessions.reload.sole.id
      assert_not_predicate session, :recently_reauthenticated?
      get settings_profile_path
      assert_response :success
      assert_includes response.body, @user.email_address
      post registration_options_passkeys_path, as: :json
      assert_response :forbidden

      post passkey_reauthentication_path, params: { credential: valid }, as: :json
      assert_response :unauthorized
      assert_equal before_credential, @credential.reload.attributes
      assert_equal before_session, session.reload.attributes

      step_up_with_passkey
      assert_predicate session.reload, :recently_reauthenticated?
      assert_equal session.id, @user.sessions.reload.sole.id
      assert_operator @credential.reload.sign_count, :>, before_credential.fetch("sign_count")
      post registration_options_passkeys_path, as: :json
      assert_response :success
    end
  end

  private

    def assertion_for(options_path)
      post options_path, as: :json
      assert_response :success
      @client.get(challenge: response.parsed_body.fetch("challenge"), user_verified: true, backup_state: false)
    end

    def with_signature(credential, signature)
      credential.deep_dup.tap do |payload|
        payload.fetch("response")["signature"] = Base64.urlsafe_encode64(signature, padding: false)
      end
    end

    def sign_in_with_passkey
      post authentication_passkeys_path, params: { credential: assertion_for(authentication_options_passkeys_path) }, as: :json
      assert_response :success
    end

    def step_up_with_passkey
      post passkey_reauthentication_path, params: { credential: assertion_for(passkey_options_reauthentication_path) }, as: :json
      assert_response :success
    end
end
