require "net/http"
require "uri"

class LoopsDelivery
  ENDPOINT = URI("https://app.loops.so/api/v1/transactional")

  def self.configured?
    api_key.present?
  end

  def self.deliver_now(email:, transactional_id:, data_variables:)
    raise MissingApiKey, "LOOPS_API_KEY is required in production" if Rails.env.production? && api_key.blank?

    return true if api_key.blank?

    request = Net::HTTP::Post.new(ENDPOINT)
    request["Authorization"] = "Bearer #{api_key}"
    request["Content-Type"] = "application/json"
    request.body = {
      email: email,
      transactionalId: transactional_id,
      dataVariables: data_variables
    }.to_json

    Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true) do |http|
      http.request(request)
    end
  end

  def self.api_key
    ENV["LOOPS_API_KEY"]
  end

  class MissingApiKey < StandardError; end
end
