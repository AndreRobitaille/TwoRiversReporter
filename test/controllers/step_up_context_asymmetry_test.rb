require "test_helper"

# One session state, two answers. Every test here starts from the same
# situation — a session whose recorded context no longer matches the request,
# whose step-up is still inside Session::REAUTH_FRESHNESS — and asserts that
# the admin boundary lets it through while the credential surface does not.
#
# That asymmetry is deliberate and each half exists for the other's sake:
#
# - The admin gate runs on every page load, so an egress that rotates its
#   address between requests would loop forever against a strict check.
# - Passkey add and remove are already gated on the same fifteen-minute window
#   by require_fresh_reauthentication. A context gate that also passed on
#   freshness would therefore add nothing, and a cookie replayed from another
#   network minutes after the victim signed in would register an attacker's
#   credential — durable access that outlives the stolen cookie, with no
#   password to change to evict it.
#
# If either half of this file passes with its guard removed, the asymmetry is
# not actually enforced.
class StepUpContextAsymmetryTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "asymmetry-admin@example.com", admin: true, status: "active")
    @member = User.create!(email_address: "asymmetry-member@example.com", status: "active")
  end

  test "a drifted context with a fresh step-up reaches the admin area" do
    session = drifted_but_fresh(@admin)

    assert_predicate session, :recently_reauthenticated?
    assert_not_equal NetworkPrefix.for("127.0.0.1"), session.ip_prefix

    get admin_root_url

    assert_response :success,
      "the admin boundary tolerates address churn, or a step-up buys exactly one page load"
  end

  test "a drifted context with a fresh step-up cannot request registration options" do
    drifted_but_fresh(@member)

    post registration_options_passkeys_url(format: :json)

    assert_response :forbidden,
      "freshness alone must not open the credential surface: that is the replayed-cookie case"
  end

  test "a drifted context with a fresh step-up cannot register a passkey" do
    drifted_but_fresh(@member)

    assert_no_difference -> { PasskeyCredential.count } do
      post registration_passkeys_url(format: :json), params: { credential: { raw: "value" } }
    end

    assert_response :forbidden
  end

  test "a drifted context with a fresh step-up cannot remove a passkey" do
    drifted_but_fresh(@member)
    credential = @member.passkey_credentials.sole

    assert_no_difference -> { PasskeyCredential.count } do
      delete passkey_url(credential)
    end

    assert_redirected_to new_reauthentication_url
    assert_predicate credential.reload, :persisted?
  end

  # The control for the three refusals above: with the context restored and
  # nothing else changed, the same request succeeds. Without this, a refusal
  # caused by something unrelated to the context would read as the gate working.
  test "the same fresh session on the recorded network can request registration options" do
    sign_in_as(@member)

    post registration_options_passkeys_url(format: :json)

    assert_response :success
  end

  test "the security page withholds passkey controls from a drifted context" do
    drifted_but_fresh(@member)

    get settings_security_url

    assert_response :success
    assert_select "button[data-action='passkey#register']", { count: 0 },
      "offering a control whose endpoint answers 403 makes passkey_controller.js report the wrong error"
    assert_select "a[href=?]", new_reauthentication_path
  end

  private

    # Signed in, freshly stepped up, and anchored to a network the request is
    # not coming from — the state a phone hopping cell towers or an iCloud
    # Private Relay egress produces within minutes of a genuine step-up.
    def drifted_but_fresh(user)
      session = sign_in_as(user)
      session.update_columns(ip_prefix: "198.51.100.0/24", reauthenticated_at: Time.current)
      session
    end
end
