module Crawlers
  class Verifier
    Outcome = Struct.new(:bot, :reason, :ip, keyword_init: true)

    def initialize(ranges: IpRanges.new, client_ip: ClientIp.new)
      @ranges = ranges
      @client_ip = client_ip
    end

    def call(request)
      outcome(request).bot
    end

    def outcome(request)
      empty = Outcome.new(bot: nil, reason: nil, ip: nil)
      return empty unless request.get? || request.head?

      user_agent = request.user_agent
      return empty unless user_agent.is_a?(String) && user_agent.ascii_only? && user_agent.bytesize <= 2048

      bots = Providers::BOTS.keys.select do |name|
        user_agent.match?(/(?:\A|[\s(;])#{Regexp.escape(name)}(?:\/[\d.]+)?(?=[\s;)]|\z)/i)
      end
      address = @client_ip.call(request)
      ip = address&.to_s
      return empty if bots.empty?
      return Outcome.new(bot: nil, reason: "ambiguous_user_agent", ip: ip) unless bots.one?
      return Outcome.new(bot: nil, reason: "missing_client_ip", ip: nil) unless address

      bot = bots.first
      status = @ranges.authorization_status(Providers::BOTS.fetch(bot), address)
      return Outcome.new(bot: bot, reason: nil, ip: ip) if status == :match

      Outcome.new(bot: nil, reason: "ranges_#{status}", ip: ip)
    end
  end
end
