require "ipaddr"

module Crawlers
  class ClientIp
    def self.parse(value)
      return unless value.is_a?(String) && value.valid_encoding?
      return unless value.match?(/\A[\da-fA-F:.]+\z/)

      address = IPAddr.new(value)
      address.ipv4_mapped? ? address.native : address
    rescue IPAddr::Error
      nil
    end

    def initialize(trusted_proxies: Rails.configuration.x.crawler_trusted_proxies)
      @trusted_proxies = trusted_proxies
    end

    def call(request)
      peer = self.class.parse(request.get_header("REMOTE_ADDR"))
      return unless peer
      return peer unless trusted?(peer)

      forwarded = request.get_header("HTTP_X_FORWARDED_FOR")
      return peer if forwarded.blank?
      return unless forwarded.valid_encoding? && forwarded.bytesize <= 4096

      hops = forwarded.split(",", -1)
      return if hops.length > 32

      addresses = hops.map { |hop| self.class.parse(hop.strip) }
      return if addresses.any?(&:nil?)

      # Start at our socket and stop at the first untrusted hop. Anything a
      # browser prepended to the chain is ignored, including a crawler IP.
      addresses.reverse.find { |address| !trusted?(address) } || peer
    end

    private

      def trusted?(address)
        @trusted_proxies.any? { |proxy| proxy.include?(address) }
      end
  end
end
