# Authentication records accumulate forever otherwise. Sessions were never
# swept at all; magic links are dead the moment they are used; sign-in attempts
# are only ever read inside a fifteen-minute window and are never read again.
#
# Idempotent by construction: it only ever deletes rows that are already
# unusable, so a second run in the same minute is a no-op.
class ExpiredAuthRecordsCleanupJob < ApplicationJob
  queue_as :default

  def perform
    delete_expired_sessions
    delete_dead_magic_links
    delete_stale_sign_in_attempts
  end

  private

    def delete_expired_sessions
      Session
        .where(last_seen_at: ...Session::INACTIVITY_LIMIT.ago)
        .or(Session.where(last_seen_at: nil))
        .or(Session.where(created_at: ...Session::ABSOLUTE_LIFETIME.ago))
        .in_batches
        .delete_all
    end

    def delete_dead_magic_links
      MagicLink
        .where.not(used_at: nil)
        .or(MagicLink.where(expires_at: ...Time.current))
        .in_batches
        .delete_all
    end

    def delete_stale_sign_in_attempts
      SignInAttempt
        .where(created_at: ...SignInAttempt::WINDOW.ago)
        .in_batches
        .delete_all
    end
end
