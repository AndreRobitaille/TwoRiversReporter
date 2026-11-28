require "net/http"
require "vips"

module Campaigns
  class PortraitImage
    class Error < StandardError; end

    HOSTS = %w[www.gannett-cdn.com media.zenfs.com media-cdn.socastsrm.com].freeze
    MAX_BYTES = 12.megabytes

    def self.allowed_url?(url)
      uri = URI.parse(url.to_s)
      uri.is_a?(URI::HTTPS) && HOSTS.include?(uri.host) && uri.userinfo.nil? && uri.port == 443
    rescue URI::InvalidURIError
      false
    end

    def self.thumbnail(url)
      raise Error, "Unrecognized publisher image address." unless allowed_url?(url)
      data = download(URI(url))
      image = case Marcel::MimeType.for(StringIO.new(data))
      when "image/jpeg" then Vips::Image.jpegload_buffer(data)
      when "image/png" then Vips::Image.pngload_buffer(data)
      else raise Error, "The publisher did not return a JPEG or PNG portrait."
      end
      raise Error, "The publisher image is too large." if image.width * image.height > 40_000_000
      thumb = Vips::Image.thumbnail_buffer(data, 240, height: 240, size: :down)
      thumb = thumb.flatten(background: [ 255 ]) if thumb.has_alpha?
      thumb.jpegsave_buffer(Q: 85, strip: true)
    rescue Vips::Error, IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
      raise Error, "Could not read the publisher image. Try again when the photo is available."
    end

    def self.download(uri)
      bytes = +"".b
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 4, read_timeout: 8) do |http|
        http.request(Net::HTTP::Get.new(uri)) do |response|
          raise Error, "The publisher image is unavailable." unless response.is_a?(Net::HTTPSuccess)
          response.read_body do |chunk|
            raise Error, "The publisher image is too large." if bytes.bytesize + chunk.bytesize > MAX_BYTES
            bytes << chunk
          end
        end
      end
      bytes
    end
    private_class_method :download
  end
end
