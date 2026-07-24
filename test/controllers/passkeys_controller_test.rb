require "test_helper"
require "ostruct"

class PasskeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "passkey@example.com", password: "password123", password_confirmation: "password123", status: "active")
    @other_user = User.create!(email_address: "other@example.com", password: "password123", password_confirmation: "password123", status: "active")
    @inactive_user = User.create!(email_address: "inactive@example.com", password: "password123", password_confirmation: "password123", status: "rejected")
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
    WebAuthn::Credential.stub(:options_for_create, ->(*args, **kwargs) { options }) do
      post registration_options_passkeys_url, headers: headers
    end

    assert_response :success
    assert_equal options.to_json, response.body
  end

  test "registration stores verified credential and clears challenge" do
    response_payload = {
      id: "credential-123",
      public_key: "public-key",
      sign_count: 0
    }

    credential = OpenStruct.new(id: "credential-123", public_key: "public-key", sign_count: 0, nickname: nil)
    headers = signed_session_headers(@user)
    WebAuthn::Credential.stub(:from_create, ->(*args, **kwargs) { credential }) do
      post registration_passkeys_url, params: { credential: { raw: "value" } }, headers: headers
    end

    assert_response :success
    stored = PasskeyCredential.find_by!(external_id: "credential-123")
    assert_equal @user, stored.user
    assert_equal "public-key", stored.public_key
  end

  test "authentication_options stores challenge without login" do
    post authentication_options_passkeys_url

    assert_response :success
    assert_predicate response.body, :present?
  end

  test "authentication rejects unknown credentials" do
    WebAuthn::Credential.stub(:from_get, OpenStruct.new(id: "missing", sign_count: 1)) do
      post authentication_passkeys_url, params: { credential: { raw: "value" } }
    end

    assert_response :not_found
  end

  test "authentication rejects inactive user" do
    credential = PasskeyCredential.create!(user: @inactive_user, external_id: "credential-123", public_key: "public-key", sign_count: 0)
    WebAuthn::Credential.stub(:from_get, OpenStruct.new(id: credential.external_id, sign_count: 1)) do
      post authentication_passkeys_url, params: { credential: { raw: "value" } }
    end

    assert_response :unauthorized
  end

  test "update and destroy only affect current user's credentials" do
    mine = PasskeyCredential.create!(user: @user, external_id: "mine", public_key: "public-key", sign_count: 0)
    other = PasskeyCredential.create!(user: @other_user, external_id: "other", public_key: "public-key", sign_count: 0)

    headers = signed_session_headers(@user)
    patch passkey_url(mine), params: { passkey_credential: { nickname: "Renamed" } }, headers: headers
    assert_equal "Renamed", mine.reload.nickname

    patch passkey_url(other), params: { passkey_credential: { nickname: "Hacked" } }, headers: headers
    assert_response :not_found
    assert_nil other.reload.nickname

    delete passkey_url(mine), headers: headers
    assert_raises(ActiveRecord::RecordNotFound) { mine.reload }
    assert_predicate other.reload, :persisted?
  end

  private

    def signed_session_headers(user)
      session = Session.create!(user: user, last_seen_at: Time.current)
      req = ActionDispatch::TestRequest.create
      jar = ActionDispatch::Cookies::CookieJar.build(req, {})
      jar.signed[:session_id] = session.id
      { "Cookie" => jar.to_header }
    end
end
