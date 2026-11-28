require "net/http"

module Campaigns
  class PublisherHttp
    Unavailable = Class.new(StandardError)

    def self.fetch(url)
      uri = URI(url)
      body = +"".b
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 45, max_retries: 0) do |http|
        request = Net::HTTP::Get.new(uri, "User-Agent" => "TwoRiversReporter-election-desk")
        http.request(request) do |response|
          raise Unavailable, "HTTP #{response.code} from #{uri.host}" unless response.is_a?(Net::HTTPSuccess)
          response.read_body do |chunk|
            raise Unavailable, "Response exceeded 5 MB." if body.bytesize + chunk.bytesize > 5.megabytes
            body << chunk
          end
        end
      end
      body
    rescue IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
      raise Unavailable, "Could not retrieve #{uri.host}."
    end
  end
end
