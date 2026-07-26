require "test_helper"

# Exercises a genuine race at the database level rather than asserting on
# implementation detail: one thread holds an uncommitted insert of a pair
# open, a second thread calls KnownContext.remember! for the exact same pair.
# Postgres blocks the second INSERT on the first transaction's uncommitted
# index entry, then — once the first commits — hands the second a real
# ActiveRecord::RecordNotUnique. remember! must survive that, not raise it.
#
# Not run inside the shared per-test transaction: both threads need their own
# connection and the first thread's row needs to actually commit for the
# second to race against, neither of which the usual transactional rollback
# allows.
class KnownContextConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @user = User.create!(email_address: "known-context-race@example.com", status: "active")
  end

  teardown do
    KnownContext.where(user: @user).delete_all
    @user.destroy
  end

  test "remember! does not raise when it races an in-flight insert of the same pair" do
    ip_prefix = "203.0.113.0/24"
    device_fingerprint = "chrome|macintosh"
    row_inserted = Queue.new
    release_writer = Queue.new
    racer_exception = nil

    writer = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction do
          KnownContext.create!(
            user: @user, ip_prefix: ip_prefix, device_fingerprint: device_fingerprint,
            last_seen_at: 1.hour.ago
          )
          row_inserted << true
          release_writer.pop # hold the transaction open until the racer is blocked on this row
        end
      end
    end

    row_inserted.pop
    sleep 0.2 # give the racer's INSERT time to reach Postgres and start waiting on the writer's lock

    racer = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        KnownContext.remember!(@user, SessionContext.new(ip_prefix: ip_prefix, device_fingerprint: device_fingerprint))
      rescue StandardError => e
        racer_exception = e
      end
    end

    sleep 0.3 # let the racer's INSERT actually start blocking before the writer commits
    release_writer << true
    writer.join
    racer.join

    assert_nil racer_exception,
      "remember! must survive a genuine unique-index race rather than raising #{racer_exception.inspect}"
    assert_equal 1, KnownContext.where(user: @user, ip_prefix: ip_prefix, device_fingerprint: device_fingerprint).count
  end
end
