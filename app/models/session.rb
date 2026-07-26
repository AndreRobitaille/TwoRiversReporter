class Session < ApplicationRecord
  belongs_to :user

  # Rolling: active use keeps a session alive, up to ABSOLUTE_LIFETIME.
  INACTIVITY_LIMIT = 60.days

  # Hard ceiling measured from creation. No session lives forever, however
  # actively it is used.
  ABSOLUTE_LIFETIME = 1.year

  TOUCH_INTERVAL = 15.minutes

  # How long a step-up counts as fresh. Matched to MagicLink's 15-minute expiry
  # so a link that took twelve minutes to arrive still grants a usable window.
  REAUTH_FRESHNESS = 15.minutes

  def inactive?
    last_seen_at.blank? || last_seen_at < INACTIVITY_LIMIT.ago
  end

  def beyond_absolute_lifetime?
    created_at.blank? || created_at < ABSOLUTE_LIFETIME.ago
  end

  def expired?
    inactive? || beyond_absolute_lifetime?
  end

  def touch_last_seen_if_stale!
    return false if last_seen_at.present? && last_seen_at >= TOUCH_INTERVAL.ago

    update!(last_seen_at: Time.current)
  end

  def recently_reauthenticated?
    reauthenticated_at.present? && reauthenticated_at >= REAUTH_FRESHNESS.ago
  end

  # A step-up both proves the person is still there and accepts wherever they
  # now are. Keeping these one operation means there is a single rule to reason
  # about: either the recorded context matches the request or it does not.
  #
  # Also the one place every step-up passes through, so remembering the
  # context here — rather than at each caller — covers every current and
  # future call site automatically. A step-up is one of only two moments the
  # user has just proved who they are (sign-in is the other, in
  # start_new_session_for); it is never called for a mere context match, so
  # this cannot be used to enrol an attacker's own network.
  def reauthenticate!(context)
    context.apply_to(self)
    self.reauthenticated_at = Time.current
    save!
    KnownContext.remember!(user, context)
  end
end
