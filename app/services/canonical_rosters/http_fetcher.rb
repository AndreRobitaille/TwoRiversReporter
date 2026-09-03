require "net/http"

module CanonicalRosters
  class HttpFetcher
    Error = Class.new(StandardError)

    def call(url)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "text/html"
      request["User-Agent"] = "TwoRiversReporter-roster-verifier"

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 10,
        read_timeout: 30
      ) { |http| http.request(request) }

      raise Error, "#{url} returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end
  end
end
