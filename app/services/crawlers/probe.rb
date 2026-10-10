module Crawlers
  class Probe
    LIFETIME = 48.hours

    def self.create_pair
      %w[public gated].index_with do |mode|
        token = SecureRandom.hex(16)
        probe = { mode: mode, code: "PROBE-#{SecureRandom.hex(12)}", expires_at: LIFETIME.from_now.to_i }
        raise IpRanges::Error, "probe cache write failed" unless Rails.cache.write(cache_key(token), probe, expires_in: LIFETIME)

        probe.merge(token: token)
      end
    end

    def self.find(token)
      return unless token.is_a?(String) && token.match?(/\A[0-9a-f]{32}\z/)

      probe = Rails.cache.read(cache_key(token))
      return unless probe.is_a?(Hash) && %w[public gated].include?(probe[:mode])
      return unless probe[:code].is_a?(String) && probe[:code].match?(/\APROBE-[0-9a-f]{24}\z/)
      return unless probe[:expires_at].is_a?(Integer) && probe[:expires_at] > Time.current.to_i

      probe
    end

    def self.cache_key(token)
      "crawlers/probes/v1/#{token}"
    end
  end
end
