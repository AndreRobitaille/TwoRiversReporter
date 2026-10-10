require "ipaddr"
require "net/http"

module Crawlers
  class IpRanges
    Error = Class.new(StandardError)
    MAX_AGE = 48.hours
    MAX_BODY_BYTES = 1.megabyte
    MAX_PREFIXES = 4096

    def initialize(cache: Rails.cache)
      @cache = cache
    end

    def include?(feed, address)
      authorization_status(feed, address) == :match
    end

    # :match, :missing, :not_current, :miss, :invalid, or :unreadable.
    # A snapshot written by refresh uses symbol keys and string prefixes.
    # String keys and IPAddr prefixes stay closed.
    def authorization_status(feed, address)
      snapshot = @cache.read(cache_key(feed))
      return :missing unless snapshot.is_a?(Hash)

      fetched_at = snapshot[:fetched_at]
      return :not_current unless fetched_at.is_a?(Integer) && fetched_at.between?(MAX_AGE.ago.to_i + 1, Time.current.to_i)

      return :match if validated_ranges(snapshot[:prefixes]).any? { |range| range.include?(address) }

      :miss
    rescue Error
      :invalid
    rescue ActiveRecord::ActiveRecordError
      :unreadable
    end

    def refresh(feed)
      url = Providers::FEEDS.fetch(feed)
      data = JSON.parse(fetch(url))
      entries = data.is_a?(Hash) ? data["prefixes"] : nil
      raise Error, "missing or empty prefixes" unless entries.is_a?(Array) && entries.length.between?(1, MAX_PREFIXES)

      prefixes = entries.map do |entry|
        raise Error, "invalid prefix entry" unless entry.is_a?(Hash)

        keys = entry.keys & %w[ipv4Prefix ipv6Prefix]
        raise Error, "ambiguous prefix entry" unless keys.one?

        prefix = entry.fetch(keys.first)
        range = validated_ranges([ prefix ]).first
        ipv4 = keys.first == "ipv4Prefix"
        raise Error, "prefix address family mismatch" unless range.ipv4? == ipv4
        prefix
      end.uniq

      snapshot = { prefixes: prefixes, fetched_at: Time.current.to_i }
      raise Error, "crawler cache write failed" unless @cache.write(cache_key(feed), snapshot, expires_in: MAX_AGE)

      prefixes.length
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Net::HTTPBadResponse, Net::ProtocolError, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError, ActiveRecord::ActiveRecordError => error
      raise Error, error.message
    end

    def cache_key(feed)
      "crawlers/ip-ranges/v1/#{feed}"
    end

    private

      def validated_ranges(prefixes)
        raise Error, "missing or empty prefixes" unless prefixes.is_a?(Array) && prefixes.length.between?(1, MAX_PREFIXES)

        prefixes.map do |prefix|
          raise Error, "invalid CIDR" unless prefix.is_a?(String) && prefix.match?(/\A[\da-fA-F:.]+\/\d{1,3}\z/)

          range = IPAddr.new(prefix)
          # A malformed feed must not accidentally authorize the internet or
          # general cloud networks. Current official feeds are narrower.
          minimum = range.ipv4? ? 16 : 32
          raise Error, "overly broad or private CIDR" if range.prefix < minimum || range.private? || range.loopback? || range.link_local?

          range
        end
      rescue IPAddr::Error
        raise Error, "invalid CIDR"
      end

      def fetch(url)
        uri = URI(url)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        request["User-Agent"] = "TwoRiversReporter-crawler-verifier"
        body = +""

        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10, write_timeout: 5) do |http|
          http.request(request) do |response|
            # Redirects are rejected too: this list is an authorization source.
            raise Error, "#{uri.host} returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

            response.read_body do |chunk|
              raise Error, "crawler feed exceeds size limit" if body.bytesize + chunk.bytesize > MAX_BODY_BYTES
              body << chunk
            end
          end
        end

        body
      end
  end
end
