require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "inactive? uses last seen timestamp" do
    user = User.create!(email_address: "active@example.com", password: "password123", password_confirmation: "password123", status: "active")

    active_session = Session.create!(user: user, last_seen_at: 1.day.ago)
    inactive_session = Session.create!(user: user, last_seen_at: 181.days.ago)
    nil_last_seen_session = Session.create!(user: user, last_seen_at: nil)

    assert_not active_session.inactive?
    assert inactive_session.inactive?
    assert nil_last_seen_session.inactive?
  end

  test "touch_last_seen_if_stale! updates only stale sessions" do
    user = User.create!(email_address: "active@example.com", password: "password123", password_confirmation: "password123", status: "active")
    session = Session.create!(user: user, last_seen_at: 20.minutes.ago)

    assert_changes -> { session.reload.last_seen_at } do
      session.touch_last_seen_if_stale!
    end

    fresh = Session.create!(user: user, last_seen_at: 5.minutes.ago)

    assert_no_changes -> { fresh.reload.last_seen_at } do
      assert_not fresh.touch_last_seen_if_stale!
    end
  end
end
