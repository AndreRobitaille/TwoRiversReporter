module Ai
  class ApiErrorDetails
    def initialize(error)
      @error = error
      @response = error.response || {}
    end

    def retryable?
      status = @response[:status].to_i
      status.zero? || [ 408, 409, 429 ].include?(status) || status >= 500
    end

    def message
      details = provider_error
      headers = @response[:headers] || {}
      fields = [ @error.message, details["message"],
        ("code=#{details['code']}" if details["code"].is_a?(String)),
        ("request_id=#{headers['x-request-id']}" if headers["x-request-id"].is_a?(String)) ]
      # Never persist the response/request dump, authorization headers or prompt.
      fields.grep(String).reject(&:blank?).join("; ").gsub(/\bsk-[\w-]+/, "[REDACTED]").truncate(1_500)
    end

    private

    def provider_error
      body = @response[:body]
      body = JSON.parse(body) if body.is_a?(String)
      body.is_a?(Hash) && body["error"].is_a?(Hash) ? body["error"] : {}
    rescue JSON::ParserError
      {}
    end
  end
end
