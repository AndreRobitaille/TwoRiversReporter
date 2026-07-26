require "test_helper"

# The backfill is the difference between a quiet deploy and every live member
# being challenged at once. These tests call SessionContextBackfill.run! —
# the same method the migration calls — so a change to the backfill fails here.
class SessionContextBackfillTest < ActiveSupport::TestCase
  test "backfill derives context from the columns already on the row" do
    user = User.create!(email_address: "backfill@example.com", status: "active")
    chrome_mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"

    row = Session.connection.select_one(<<~SQL.squish)
      INSERT INTO sessions (user_id, user_agent, ip_address, last_seen_at, created_at, updated_at)
      VALUES (#{user.id}, '#{chrome_mac}', '203.0.113.45', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING id
    SQL

    session = Session.find(row["id"])
    session.update_columns(ip_prefix: nil, device_fingerprint: nil, reauthenticated_at: nil)

    SessionContextBackfill.run!

    session.reload
    assert_equal "203.0.113.0/24", session.ip_prefix
    assert_equal "chrome|macintosh", session.device_fingerprint
    assert_equal session.created_at.to_i, session.reauthenticated_at.to_i
  end

  test "a backfilled session matches a request from the same network and browser" do
    user = User.create!(email_address: "matching@example.com", status: "active")
    chrome_mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"

    session = Session.create!(user: user, ip_address: "203.0.113.45", user_agent: chrome_mac, last_seen_at: Time.current)
    session.update_columns(ip_prefix: nil, device_fingerprint: nil)

    SessionContextBackfill.run!

    context = SessionContext.new(
      ip_prefix: NetworkPrefix.for("203.0.113.99"),
      device_fingerprint: DeviceFingerprint.for(chrome_mac.sub("141.0.0.0", "142.0.0.0"))
    )

    assert context.matches?(session.reload),
      "a backfilled session still matches after a browser update and an address change inside the same /24"
  end

  test "run! reports how many rows it touched and leaves stamped rows alone" do
    user = User.create!(email_address: "counted@example.com", status: "active")

    already_stamped = Session.create!(
      user: user, ip_address: "198.51.100.7", user_agent: nil,
      ip_prefix: "10.0.0.0/24", device_fingerprint: "kept|value", last_seen_at: Time.current
    )
    Session.create!(user: user, ip_address: "203.0.113.45", user_agent: nil, last_seen_at: Time.current)
      .update_columns(ip_prefix: nil, device_fingerprint: nil)

    assert_equal 1, SessionContextBackfill.run!,
      "only rows with no context at all are candidates"
    assert_equal "10.0.0.0/24", already_stamped.reload.ip_prefix,
      "an already-anchored session must not be re-derived; that would silently re-anchor a live session"
  end
end
