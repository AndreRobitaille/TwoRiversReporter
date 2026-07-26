require "test_helper"

class SessionContextTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "context@example.com", status: "active")
  end

  test "matches? requires both the prefix and the fingerprint" do
    session = build_session(ip_prefix: "203.0.113.0/24", device_fingerprint: "chrome|macintosh")

    assert context("203.0.113.0/24", "chrome|macintosh").matches?(session)
    assert_not context("198.51.100.0/24", "chrome|macintosh").matches?(session), "a different network does not match"
    assert_not context("203.0.113.0/24", "safari|iphone").matches?(session), "a different browser does not match"
    assert_not context("198.51.100.0/24", "safari|iphone").matches?(session)
  end

  test "a recorded nil does not match a present value" do
    session = build_session(ip_prefix: nil, device_fingerprint: nil)

    assert_not context("203.0.113.0/24", "chrome|macintosh").matches?(session),
      "an unstamped session must not match a real request, or a row created outside the sign-in path would be ungated"
  end

  test "two undetermined contexts match" do
    session = build_session(ip_prefix: nil, device_fingerprint: nil)

    assert context(nil, nil).matches?(session)
  end

  test "matches? is false for a nil session" do
    assert_not context("203.0.113.0/24", "chrome|macintosh").matches?(nil)
  end

  test "apply_to writes both fields onto the session" do
    session = build_session(ip_prefix: "198.51.100.0/24", device_fingerprint: "safari|iphone")

    context("203.0.113.0/24", "chrome|macintosh").apply_to(session)

    assert_equal "203.0.113.0/24", session.ip_prefix
    assert_equal "chrome|macintosh", session.device_fingerprint
  end

  test "from_request derives both fields from the request" do
    request = ActionDispatch::TestRequest.create(
      "REMOTE_ADDR" => "203.0.113.45",
      "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
    )

    derived = SessionContext.from_request(request)

    assert_equal "203.0.113.0/24", derived.ip_prefix
    assert_equal "chrome|macintosh", derived.device_fingerprint
  end

  test "recently_reauthenticated? honours the freshness window" do
    fresh = build_session(reauthenticated_at: 1.minute.ago)
    stale = build_session(reauthenticated_at: 16.minutes.ago)
    never = build_session(reauthenticated_at: nil)

    assert fresh.recently_reauthenticated?
    assert_not stale.recently_reauthenticated?
    assert_not never.recently_reauthenticated?
  end

  test "reauthenticate! stamps the time and adopts the new context" do
    session = build_session(ip_prefix: "198.51.100.0/24", device_fingerprint: "safari|iphone", reauthenticated_at: 2.hours.ago)

    session.reauthenticate!(context("203.0.113.0/24", "chrome|macintosh"))

    session.reload
    assert_equal "203.0.113.0/24", session.ip_prefix
    assert_equal "chrome|macintosh", session.device_fingerprint
    assert session.recently_reauthenticated?
    assert context("203.0.113.0/24", "chrome|macintosh").matches?(session),
      "accepting a new network and proving you are still there are the same operation"
  end

  test "reauthenticate! remembers the new context as known for this user" do
    session = build_session(ip_prefix: "198.51.100.0/24", device_fingerprint: "safari|iphone", reauthenticated_at: 2.hours.ago)

    session.reauthenticate!(context("203.0.113.0/24", "chrome|macintosh"))

    assert KnownContext.known?(@user, context("203.0.113.0/24", "chrome|macintosh")),
      "a successful step-up is a proof of identity and should enrol its new context, just like a fresh sign-in does"
  end

  private

    def context(ip_prefix, device_fingerprint)
      SessionContext.new(ip_prefix: ip_prefix, device_fingerprint: device_fingerprint)
    end

    def build_session(**attributes)
      Session.create!({ user: @user, last_seen_at: Time.current }.merge(attributes))
    end
end
