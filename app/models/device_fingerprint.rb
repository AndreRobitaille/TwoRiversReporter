require "useragent"

# Reduces a user-agent string to a browser family and platform, discarding the
# version. Exact user-agent matching would report a new device on every Chrome
# auto-update — roughly monthly, for every user.
#
# Deliberately coarse: "chrome|macintosh" cannot tell two Chrome-on-macOS
# machines apart. The network prefix is what separates those. What the two
# signals catch together is a cookie replayed from another network in another
# browser, which trips both.
class DeviceFingerprint
  def self.for(user_agent_string)
    # UserAgent.parse never raises and never returns a nil browser: it echoes
    # junk back, so parse(nil).browser is "Mozilla". Blank input has to be
    # rejected here or every request without a header shares one fingerprint.
    return nil if user_agent_string.blank?

    agent = UserAgent.parse(user_agent_string.to_s)
    "#{agent.browser}|#{agent.platform}".downcase
  rescue ArgumentError, EncodingError
    # The User-Agent header is entirely attacker-controlled, and `blank?`
    # raises ArgumentError on a string carrying an invalid byte sequence for
    # its encoding — before UserAgent.parse is ever reached. Without this,
    # `User-Agent: \xFF` is a 500 on every request that carries it, and this
    # method runs on every request.
    #
    # ArgumentError also subsumes anything UserAgent might raise on a
    # pathological header; EncodingError covers a non-ASCII-compatible
    # encoding surviving `blank?` and failing later.
    nil
  end
end
