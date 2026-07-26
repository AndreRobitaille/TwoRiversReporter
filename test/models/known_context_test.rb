require "test_helper"

class KnownContextTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "known-context@example.com", status: "active")
  end

  test "remember! records a new pair with last_seen_at set to now" do
    KnownContext.remember!(@user, context("203.0.113.0/24", "chrome|macintosh"))

    known = @user.known_contexts.sole
    assert_equal "203.0.113.0/24", known.ip_prefix
    assert_equal "chrome|macintosh", known.device_fingerprint
    assert_in_delta Time.current, known.last_seen_at, 5.seconds
  end

  test "remember! does not record a context whose ip_prefix and device_fingerprint are both nil" do
    KnownContext.remember!(@user, context(nil, nil))

    assert_equal 0, @user.known_contexts.count
  end

  test "remember! still records a context with only one field present" do
    KnownContext.remember!(@user, context("203.0.113.0/24", nil))
    KnownContext.remember!(@user, context(nil, "chrome|macintosh"))

    assert_equal 2, @user.known_contexts.count
  end

  test "remember! refreshes last_seen_at for an already-known pair instead of duplicating it" do
    KnownContext.remember!(@user, context("203.0.113.0/24", "chrome|macintosh"))
    known = @user.known_contexts.sole
    known.update_columns(last_seen_at: 5.days.ago)

    KnownContext.remember!(@user, context("203.0.113.0/24", "chrome|macintosh"))

    assert_equal 1, @user.known_contexts.count
    assert_in_delta Time.current, known.reload.last_seen_at, 5.seconds
  end

  test "remember! evicts the least-recently-seen context once the cap is exceeded" do
    KnownContext::MAX_PER_USER.times do |n|
      KnownContext.remember!(@user, context(nil, "browser-#{n}"))
    end
    # Stagger last_seen_at so there is one unambiguous least-recently-seen row.
    @user.known_contexts.order(:created_at).each_with_index do |kc, i|
      kc.update_columns(last_seen_at: (KnownContext::MAX_PER_USER - i).days.ago)
    end
    stalest = @user.known_contexts.order(:last_seen_at).first
    freshest_ids = @user.known_contexts.where.not(id: stalest.id).pluck(:id)

    KnownContext.remember!(@user, context(nil, "browser-new"))

    assert_equal KnownContext::MAX_PER_USER, @user.known_contexts.count
    assert_not KnownContext.exists?(stalest.id),
      "the least-recently-seen context should have been evicted to make room"
    freshest_ids.each do |id|
      assert KnownContext.exists?(id), "a more recently seen context must not be evicted in its place"
    end
    assert @user.known_contexts.exists?(device_fingerprint: "browser-new")
  end

  test "known? is true for a remembered pair and false for one never seen" do
    KnownContext.remember!(@user, context("203.0.113.0/24", "chrome|macintosh"))

    assert KnownContext.known?(@user, context("203.0.113.0/24", "chrome|macintosh"))
    assert_not KnownContext.known?(@user, context("198.51.100.0/24", "chrome|macintosh"))
  end

  test "known? is scoped per user" do
    other = User.create!(email_address: "known-context-other@example.com", status: "active")
    KnownContext.remember!(@user, context("203.0.113.0/24", "chrome|macintosh"))

    assert_not KnownContext.known?(other, context("203.0.113.0/24", "chrome|macintosh"))
  end

  test "known? does not record a pair that was never remembered" do
    assert_not KnownContext.known?(@user, context("203.0.113.0/24", "chrome|macintosh"))

    assert_equal 0, @user.known_contexts.count
  end

  test "known? does not touch last_seen_at inside the touch interval" do
    KnownContext.remember!(@user, context("203.0.113.0/24", "chrome|macintosh"))
    known = @user.known_contexts.sole
    known.update_columns(last_seen_at: 2.hours.ago)

    KnownContext.known?(@user, context("203.0.113.0/24", "chrome|macintosh"))

    assert_in_delta 2.hours.ago, known.reload.last_seen_at, 5.seconds,
      "a match inside the touch interval must not rewrite last_seen_at yet"
  end

  test "known? touches last_seen_at once the touch interval has passed" do
    KnownContext.remember!(@user, context("203.0.113.0/24", "chrome|macintosh"))
    known = @user.known_contexts.sole
    known.update_columns(last_seen_at: (KnownContext::TOUCH_INTERVAL + 1.hour).ago)

    KnownContext.known?(@user, context("203.0.113.0/24", "chrome|macintosh"))

    assert_in_delta Time.current, known.reload.last_seen_at, 5.seconds
  end

  test "destroying a user destroys their known contexts rather than orphaning them" do
    KnownContext.remember!(@user, context("203.0.113.0/24", "chrome|macintosh"))
    known = @user.known_contexts.sole

    @user.destroy!

    assert_not KnownContext.exists?(known.id),
      "a KnownContext row is worthless without its user, unlike the :nullify associations on User"
  end

  private

    def context(ip_prefix, device_fingerprint)
      SessionContext.new(ip_prefix: ip_prefix, device_fingerprint: device_fingerprint)
    end
end
