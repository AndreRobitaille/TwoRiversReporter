require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "inactive? uses last seen timestamp" do
    user = User.create!(email_address: "active@example.com", status: "active")

    active_session = Session.create!(user: user, last_seen_at: 1.day.ago)
    inactive_session = Session.create!(user: user, last_seen_at: 181.days.ago)
    nil_last_seen_session = Session.create!(user: user, last_seen_at: nil)

    assert_not active_session.inactive?
    assert inactive_session.inactive?
    assert nil_last_seen_session.inactive?
  end

  test "migration backfills nil last_seen_at to keep existing sessions active" do
    user = User.create!(email_address: "migration@example.com", status: "active")

    session = Session.connection.select_one(<<~SQL.squish)
      INSERT INTO sessions (user_id, user_agent, ip_address, last_seen_at, created_at, updated_at)
      VALUES (#{user.id}, 'test', '127.0.0.1', NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING *
    SQL

    migrated = Session.find(session["id"])

    assert migrated.inactive?

    Session.connection.execute(<<~SQL.squish)
      UPDATE sessions
      SET last_seen_at = CURRENT_TIMESTAMP
      WHERE last_seen_at IS NULL
    SQL

    assert_not Session.find(session["id"]).inactive?
  end

  test "touch_last_seen_if_stale! updates only stale sessions" do
    user = User.create!(email_address: "active@example.com", status: "active")
    session = Session.create!(user: user, last_seen_at: 20.minutes.ago)

    assert_changes -> { session.reload.last_seen_at } do
      session.touch_last_seen_if_stale!
    end

    fresh = Session.create!(user: user, last_seen_at: 5.minutes.ago)

    assert_no_changes -> { fresh.reload.last_seen_at } do
      assert_not fresh.touch_last_seen_if_stale!
    end
  end

  test "inactivity limit is sixty days" do
    assert_equal 60.days, Session::INACTIVITY_LIMIT
  end

  test "beyond_absolute_lifetime? uses created_at regardless of recent use" do
    user = User.create!(email_address: "absolute@example.com", status: "active")

    fresh = Session.create!(user: user, last_seen_at: Time.current)
    old = Session.create!(user: user, last_seen_at: Time.current)
    old.update_columns(created_at: 400.days.ago)

    assert_not fresh.beyond_absolute_lifetime?
    assert old.reload.beyond_absolute_lifetime?
  end

  test "expired? is true for either cause independently" do
    user = User.create!(email_address: "expired@example.com", status: "active")

    live = Session.create!(user: user, last_seen_at: 1.day.ago)

    idle = Session.create!(user: user, last_seen_at: 61.days.ago)

    aged = Session.create!(user: user, last_seen_at: Time.current)
    aged.update_columns(created_at: 400.days.ago)

    assert_not live.expired?
    assert idle.expired?, "a session idle past the inactivity limit is expired"
    assert aged.reload.expired?, "a session past the absolute lifetime is expired even when actively used"
  end
end
