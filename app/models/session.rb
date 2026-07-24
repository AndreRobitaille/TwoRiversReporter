class Session < ApplicationRecord
  belongs_to :user

  INACTIVITY_LIMIT = 180.days
  TOUCH_INTERVAL = 15.minutes

  def inactive?
    last_seen_at.blank? || last_seen_at < INACTIVITY_LIMIT.ago
  end

  def touch_last_seen_if_stale!
    return false if last_seen_at.present? && last_seen_at >= TOUCH_INTERVAL.ago

    update!(last_seen_at: Time.current)
  end
end
