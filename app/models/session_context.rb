# The pair of weak signals a session is anchored to: which network it was last
# seen on, and which browser family and platform it was last seen in.
#
# Neither is strong on its own and neither is treated as strong. Their job is
# to notice that a session cookie is being used somewhere it has not been used
# before, which is what a step-up challenge answers.
class SessionContext
  attr_reader :ip_prefix, :device_fingerprint

  def self.from_request(request)
    new(
      ip_prefix: NetworkPrefix.for(request.remote_ip),
      device_fingerprint: DeviceFingerprint.for(request.user_agent)
    )
  end

  def initialize(ip_prefix:, device_fingerprint:)
    @ip_prefix = ip_prefix
    @device_fingerprint = device_fingerprint
  end

  # Strict equality on both fields, including nil. A session row that was never
  # stamped — created in a console, or by a code path that forgot — records nil
  # and therefore matches no real request. That is deliberate: the alternative
  # is a row that silently satisfies every context check.
  def matches?(session)
    return false if session.nil?

    session.ip_prefix == ip_prefix && session.device_fingerprint == device_fingerprint
  end

  def apply_to(session)
    session.ip_prefix = ip_prefix
    session.device_fingerprint = device_fingerprint
    session
  end
end
