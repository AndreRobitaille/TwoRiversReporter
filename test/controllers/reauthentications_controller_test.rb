require "test_helper"
require "ostruct"

class ReauthenticationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "stepup@example.com", status: "active")
  end

  # If this controller were itself gated, an unverified context would redirect
  # to the page that fixes an unverified context, and every admin would be
  # locked out simultaneously. This is the single most important test here.
  test "the challenge page is reachable from an unverified context" do
    session = sign_in_as(@user)
    session.update_columns(ip_prefix: "198.51.100.0/24", device_fingerprint: "safari|iphone")

    get new_reauthentication_url

    assert_response :success
  end

  test "the challenge page is reachable with a long-stale reauthentication" do
    session = sign_in_as(@user)
    session.update_columns(reauthenticated_at: 1.year.ago)

    get new_reauthentication_url

    assert_response :success
  end

  test "the challenge page requires a signed-in session" do
    get new_reauthentication_url

    assert_redirected_to new_public_session_url
  end

  test "the passkey button is offered when the user has a credential" do
    sign_in_as(@user)

    get new_reauthentication_url

    assert_select "button[data-action='passkey#authenticate']", count: 1
  end

  test "the passkey button is omitted when the user has no credential" do
    session = Session.create!(
      user: @user, user_agent: nil, ip_address: "127.0.0.1",
      ip_prefix: NetworkPrefix.for("127.0.0.1"),
      device_fingerprint: DeviceFingerprint.for(nil),
      reauthenticated_at: Time.current, last_seen_at: Time.current
    )
    sign_in_with_session(session)

    get new_reauthentication_url

    assert_response :success
    assert_select "button[data-action='passkey#authenticate']", { count: 0 },
      "offering a passkey button to someone with no passkey gives them a button that cannot work"
    assert_select "form[action=?]", magic_link_reauthentication_path
  end

  test "the magic link path emails a sign-in link to the current user" do
    sign_in_as(@user)

    assert_difference -> { MagicLink.where(user: @user, purpose: "sign_in").count }, 1 do
      post magic_link_reauthentication_url
    end

    assert_redirected_to new_reauthentication_url
  end

  test "the magic link path does not burn the sign-in throttle" do
    sign_in_as(@user)

    post magic_link_reauthentication_url

    assert_not SignInAttempt.throttled?(@user.email_address),
      "a member must not be able to lock themselves out of the sign-in form from inside the app"
  end

  test "passkey_options rejects an unauthenticated caller" do
    post passkey_options_reauthentication_url(format: :json)

    assert_response :redirect
  end

  # Rejected before either ownership check ever runs: "cred-other" is not
  # valid base64url, so WebAuthn::Credential.from_get raises ArgumentError
  # while decoding the credential's rawId (WebAuthn::PublicKeyCredential.from_client).
  # WebauthnVerification#webauthn_credential_from_get catches that ArgumentError
  # and calls head :unauthorized before a `credential` object even exists — so
  # neither verified_get_credential's own (deliberately unscoped, needed to look
  # up the public key for signature verification) find_by, nor the
  # Current.user-scoped ownership check in #passkey below it, is ever reached.
  # Confirmed with `WebAuthn::Encoder.new.decode("cred-other")`, which raises
  # `ArgumentError: invalid base64` directly. A validly signed assertion for
  # another account's credential — which would actually reach the ownership
  # check — cannot be constructed in a test without a real authenticator.
  test "another user's passkey cannot step up this session" do
    other = User.create!(email_address: "other@example.com", status: "active")
    other.passkey_credentials.create!(external_id: "cred-other", public_key: "public-key", sign_count: 0)
    sign_in_as(@user)
    @user.sessions.sole.update_columns(reauthenticated_at: 1.year.ago)

    post passkey_reauthentication_url(format: :json), params: {
      credential: { id: "cred-other", rawId: "cred-other", type: "public-key",
                    response: { clientDataJSON: "e30", authenticatorData: "e30", signature: "e30" } }
    }, as: :json

    assert_response :unauthorized
    assert_not @user.sessions.sole.reload.recently_reauthenticated?
  end

  # Unlike the forged-assertion test above, this one exercises the real
  # #passkey ownership scope directly: it stubs WebAuthn::Credential.from_get
  # (the same idiom PasskeysControllerTest uses) to hand back a verified
  # credential whose id genuinely belongs to another account's
  # PasskeyCredential row, bypassing only the cryptographic ceremony a real
  # authenticator would perform. verified_get_credential's own unscoped
  # find_by legitimately locates that row (it exists — it just isn't the
  # signed-in user's), calls the stubbed `verify`, and hands the credential
  # back to #passkey, which must then reject it via Current.user scoping.
  test "another user's real passkey is rejected by the ownership scope, not by verification" do
    other = User.create!(email_address: "other-real-passkey@example.com", status: "active")
    other_credential = other.passkey_credentials.create!(external_id: "cred-other-real", public_key: "public-key", sign_count: 0)
    sign_in_as(@user)
    @user.sessions.sole.update_columns(reauthenticated_at: 1.year.ago)

    verified_credential = OpenStruct.new(id: other_credential.external_id, sign_count: 1)
    verified_credential.define_singleton_method(:verify) do |challenge, public_key:, sign_count:, user_verification:|
      true
    end

    WebAuthn::Credential.stub(:from_get, ->(*args, **kwargs) { verified_credential }) do
      post passkey_reauthentication_url(format: :json), params: { credential: { raw: "value" } }, as: :json
    end

    assert_response :unauthorized
    assert_not @user.sessions.sole.reload.recently_reauthenticated?
    assert_equal 0, other_credential.reload.sign_count,
      "the other account's credential must not be updated by a step-up it did not authorize"
  end
end
