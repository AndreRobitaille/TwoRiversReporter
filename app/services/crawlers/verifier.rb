module Crawlers
  class Verifier
    def initialize(ranges: IpRanges.new, client_ip: ClientIp.new)
      @ranges = ranges
      @client_ip = client_ip
    end

    def call(request)
      return unless request.get? || request.head?

      user_agent = request.user_agent
      return unless user_agent.is_a?(String) && user_agent.ascii_only? && user_agent.bytesize <= 2048

      bots = Providers::BOTS.keys.select do |name|
        user_agent.match?(/(?:\A|[\s(;])#{Regexp.escape(name)}(?:\/[\d.]+)?(?=[\s;)]|\z)/i)
      end
      return unless bots.one?

      bot = bots.first
      address = @client_ip.call(request)
      bot if address && @ranges.include?(Providers::BOTS.fetch(bot), address)
    end
  end
end
