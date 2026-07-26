require "test_helper"

class ExpiredAuthRecordsCleanupJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(email_address: "sweeper@example.com", status: "active")
  end

  test "deletes sessions idle past the inactivity limit" do
    live = Session.create!(user: @user, last_seen_at: 1.day.ago)
    idle = Session.create!(user: @user, last_seen_at: 61.days.ago)

    ExpiredAuthRecordsCleanupJob.perform_now

    assert Session.exists?(live.id)
    assert_not Session.exists?(idle.id)
  end

  test "deletes sessions past the absolute lifetime even when actively used" do
    aged = Session.create!(user: @user, last_seen_at: Time.current)
    aged.update_columns(created_at: 400.days.ago)

    ExpiredAuthRecordsCleanupJob.perform_now

    assert_not Session.exists?(aged.id)
  end

  test "deletes used and expired magic links but keeps usable ones" do
    usable = MagicLink.create_for!(@user, purpose: "sign_in")
    used = MagicLink.create_for!(@user, purpose: "sign_in")
    used.update!(used_at: Time.current)
    expired = MagicLink.create_for!(@user, purpose: "sign_in", expires_at: 1.hour.ago)

    ExpiredAuthRecordsCleanupJob.perform_now

    assert MagicLink.exists?(usable.id)
    assert_not MagicLink.exists?(used.id)
    assert_not MagicLink.exists?(expired.id)
  end

  test "deletes sign in attempts past the throttle window but keeps live ones" do
    live = SignInAttempt.record!("live@example.com")
    old = SignInAttempt.record!("old@example.com")
    old.update_columns(created_at: 1.day.ago)

    ExpiredAuthRecordsCleanupJob.perform_now

    assert SignInAttempt.exists?(live.id)
    assert_not SignInAttempt.exists?(old.id)
  end

  test "is idempotent" do
    Session.create!(user: @user, last_seen_at: 61.days.ago)

    ExpiredAuthRecordsCleanupJob.perform_now
    assert_nothing_raised { ExpiredAuthRecordsCleanupJob.perform_now }
  end
end
