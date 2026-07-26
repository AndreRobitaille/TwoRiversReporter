require "test_helper"

# Proves the whole point of KnownContext: a session whose anchor no longer
# matches the request can still pass a context gate when the pair has been
# proved before for this user. Run against the STRICT gate
# (PasskeysController#registration_options) rather than the tolerant admin
# gate, because the tolerant gate has another way through (a recent step-up)
# that would let a broken KnownContext wiring pass this test for the wrong
# reason.
class KnownContextGateTest < ActionDispatch::IntegrationTest
  setup do
    @member = User.create!(email_address: "known-context-gate@example.com", status: "active")
  end

  test "a known context lets a mismatched-anchor session through the strict gate" do
    session = sign_in_as(@member)
    session.update_columns(ip_prefix: "198.51.100.0/24")
    assert_not_equal NetworkPrefix.for("127.0.0.1"), session.ip_prefix,
      "the session's own anchor must actually mismatch the request, or this proves nothing about KnownContext"

    KnownContext.remember!(@member, SessionContext.new(
      ip_prefix: NetworkPrefix.for("127.0.0.1"), device_fingerprint: DeviceFingerprint.for(nil)
    ))

    post registration_options_passkeys_url(format: :json)

    assert_response :success,
      "a context already proved for this user should satisfy the strict gate even though the session's own anchor has moved"
  end

  test "an unremembered mismatched context is still denied" do
    session = sign_in_as(@member)
    session.update_columns(ip_prefix: "198.51.100.0/24")

    post registration_options_passkeys_url(format: :json)

    assert_response :forbidden,
      "the gate must not pass on a mismatch alone; only a genuinely known context should rescue it"
  end

  test "passing the gate on a matching anchor does not itself enrol a context" do
    sign_in_as(@member)

    post registration_options_passkeys_url(format: :json)

    assert_response :success
    assert_equal 0, @member.known_contexts.count,
      "a mere gate pass must not enrol a context, or an attacker's own network would enrol itself the moment it slips through some other way"
  end
end
