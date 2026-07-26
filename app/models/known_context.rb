# A learned baseline of the (ip_prefix, device_fingerprint) pairs a user has
# actually signed in or stepped up from before, so the context gates can ask
# "have I seen this before?" rather than only "does this match the last
# request?" — comparing against the last request alone challenges on every
# network change, which is not what mature identity providers do.
#
# The pair is the unit, not the prefix alone: remembering only the network
# would discard the device half, which is the stronger of the two signals — a
# new browser on a familiar network is still worth asking about.
class KnownContext < ApplicationRecord
  belongs_to :user

  MAX_PER_USER = 10
  RETENTION = 90.days

  # How often a matching request refreshes last_seen_at. Coarser than
  # Session::TOUCH_INTERVAL (15 minutes) on purpose: this timestamp only
  # decides whether a context survives the 90-day sweep, not whether a session
  # is alive, so there is nothing to gain from writing it on every request.
  TOUCH_INTERVAL = 1.day

  # Recorded only at sign-in and at a successful step-up — both are moments the
  # user has just proved who they are. Never called for a mere context match:
  # doing so would let an attacker's own network enrol itself the first time it
  # slips past the gate on some other basis, after which it would pass outright.
  #
  # A context whose ip_prefix and device_fingerprint are both nil is refused:
  # it carries no information and would match every other undetermined
  # request.
  #
  # Concurrency: two requests racing to remember the same new pair both hit
  # create_or_find_by!, which rescues the unique-index violation and re-reads
  # instead of raising. The unique index carries nulls_not_distinct so this
  # holds even when one or both fields are nil.
  def self.remember!(user, context)
    return if context.ip_prefix.nil? && context.device_fingerprint.nil?

    known = create_or_find_by!(
      user: user,
      ip_prefix: context.ip_prefix,
      device_fingerprint: context.device_fingerprint
    ) do |record|
      record.last_seen_at = Time.current
    end
    known.update!(last_seen_at: Time.current)

    evict_beyond_cap!(user)
  end

  # Whether this pair has been seen before for this user. Touches last_seen_at
  # at most once per TOUCH_INTERVAL on a hit so an actively used context does
  # not age out while a genuinely abandoned one does — but never records a
  # pair that was not already known; see remember! for why that matters.
  def self.known?(user, context)
    known = user.known_contexts.find_by(
      ip_prefix: context.ip_prefix,
      device_fingerprint: context.device_fingerprint
    )
    return false unless known

    known.touch_last_seen_if_stale!
    true
  end

  def touch_last_seen_if_stale!
    return false if last_seen_at.present? && last_seen_at >= TOUCH_INTERVAL.ago

    update!(last_seen_at: Time.current)
  end

  private_class_method def self.evict_beyond_cap!(user)
    ids_to_keep = user.known_contexts.order(last_seen_at: :desc).limit(MAX_PER_USER).pluck(:id)
    user.known_contexts.where.not(id: ids_to_keep).delete_all
  end
end
