require "ipaddr"

# Reduces an IP address to the network it sits on, so that a session survives
# the address churn that is normal on mobile networks while a genuine move to
# another provider or another city still registers as a change.
#
# /24 for IPv4 and /48 for IPv6. IPv6 subscriber allocations are typically /48
# or /56, so /48 is the more forgiving of the two plausible choices.
class NetworkPrefix
  IPV4_MASK = 24
  IPV6_MASK = 48

  def self.for(ip_string)
    return nil if ip_string.blank?

    address = IPAddr.new(ip_string.to_s.strip)

    # "::ffff:203.0.113.45" and "203.0.113.45" are the same host. Without this
    # the same machine yields two different prefixes depending on which form
    # the proxy happened to hand us, and every such switch looks like a move.
    address = address.native if address.ipv4_mapped?

    mask = address.ipv4? ? IPV4_MASK : IPV6_MASK
    "#{address.mask(mask)}/#{mask}"
  rescue IPAddr::Error
    nil
  end
end
