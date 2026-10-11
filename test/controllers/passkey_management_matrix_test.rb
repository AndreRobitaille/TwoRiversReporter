require "test_helper"

class PasskeyManagementMatrixTest < ActionDispatch::IntegrationTest
  STATES = {
    fresh_anchor: { fresh: true, matching: true, known: false, page: true, endpoint: true },
    fresh_known_pair: { fresh: true, matching: false, known: true, page: false, endpoint: true },
    fresh_unknown_pair: { fresh: true, matching: false, known: false, page: false, endpoint: false },
    stale_anchor: { fresh: false, matching: true, known: false, page: false, endpoint: false },
    stale_known_pair: { fresh: false, matching: false, known: true, page: false, endpoint: false }
  }.freeze

  STATES.each do |name, state|
    test "#{name} rendered controls and direct credential endpoints" do
      user = User.create!(email_address: "matrix-#{name}@example.com", status: "active")
      credential = user.passkey_credentials.create!(external_id: "matrix-#{name}", public_key: "fixture", sign_count: 0)
      anchor_ip = state[:matching] ? "127.0.0.1" : "192.0.2.1"
      sign_in_with_session(user.sessions.create!(ip_address: anchor_ip, ip_prefix: NetworkPrefix.for(anchor_ip),
        device_fingerprint: DeviceFingerprint.for(nil), reauthenticated_at: state[:fresh] ? Time.current : 16.minutes.ago,
        last_seen_at: Time.current))
      if state[:known]
        KnownContext.create!(user: user, ip_prefix: NetworkPrefix.for("127.0.0.1"), device_fingerprint: DeviceFingerprint.for(nil), last_seen_at: Time.current)
      end
      before = credential.attributes
      audit_count = AuditEvent.count
      get settings_security_path
      assert_response :success
      assert_select "[data-action='passkey#register']", count: state[:page] ? 1 : 0
      assert_select "a[href=?][data-turbo-method=delete]", passkey_path(credential), count: state[:page] ? 1 : 0
      assert_select "a[href=?]", new_reauthentication_path, count: state[:page] ? 0 : 1

      # This fresh-known row intentionally characterizes the unresolved mismatch:
      # the current page blocks while the additive strict endpoint gate passes.
      post registration_options_passkeys_path(format: :json)
      assert_response state[:endpoint] ? :success : :forbidden
      assert response.parsed_body.fetch("challenge").present? if state[:endpoint]
      post registration_passkeys_path(format: :json), params: { credential: { malformed: true } }
      assert_response state[:endpoint] ? :unprocessable_entity : :forbidden
      assert_equal before, credential.reload.attributes
      assert_equal audit_count, AuditEvent.count

      delete passkey_path(credential, format: :json)
      if state[:endpoint]
        assert_redirected_to settings_security_path
        assert_not PasskeyCredential.exists?(credential.id)
        get settings_security_path
        assert_select "a[href=?][data-turbo-method=delete]", passkey_path(credential), count: 0
      else
        assert_response :forbidden
        assert_equal before, credential.reload.attributes
        delete passkey_path(credential), headers: { "HTTP_REFERER" => settings_security_url }
        assert_redirected_to new_reauthentication_path
        assert_equal before, credential.reload.attributes
        follow_redirect!
        assert_select "button[data-action='passkey#authenticate']"
        assert_select "form[action=?]", magic_link_reauthentication_path
        assert_equal before, credential.reload.attributes, "GET challenge must not replay deletion"
      end
      assert_equal audit_count, AuditEvent.count
    end
  end

  test "fresh owner sees own control but foreign IDs and last usable admin removal preserve state" do
    admin = User.create!(email_address: "matrix-last-admin@example.com", status: "active", admin: true)
    other = User.create!(email_address: "matrix-other-resident@example.com", status: "active")
    mine = admin.passkey_credentials.create!(external_id: "matrix-last-admin", public_key: "fixture", sign_count: 0)
    theirs = other.passkey_credentials.create!(external_id: "matrix-foreign", public_key: "fixture", sign_count: 0)
    sign_in_as(admin)
    before = [ mine.attributes, theirs.attributes ]
    audit_count = AuditEvent.count
    get settings_security_path
    assert_select "a[href=?][data-turbo-method=delete]", passkey_path(mine)
    assert_select "a[href=?]", passkey_path(theirs), count: 0
    [ :html, :json ].each do |format|
      delete passkey_path(theirs, format: format)
      assert_response :not_found
      assert_equal before, [ mine.reload.attributes, theirs.reload.attributes ]
    end
    delete passkey_path(mine)
    assert_redirected_to settings_security_path
    assert_equal "At least one active admin with a passkey must remain.", flash[:alert]
    assert_equal before, [ mine.reload.attributes, theirs.reload.attributes ]
    assert_equal audit_count, AuditEvent.count
    get settings_security_path
    assert_select "a[href=?][data-turbo-method=delete]", passkey_path(mine)
  end
end
