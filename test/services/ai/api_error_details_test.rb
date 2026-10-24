require "test_helper"

class Ai::ApiErrorDetailsTest < ActiveSupport::TestCase
  test "keeps actionable error fields but excludes credentials and request payloads" do
    error = Faraday::BadRequestError.new("HTTP 400", {
      status: 400, body: { "error" => { "message" => "Invalid parameter sk-private-key", "code" => "invalid_value" }, "other" => "UNRELATED_RESPONSE" },
      headers: { "x-request-id" => "req-diagnostic", "authorization" => "SECRET_HEADER" },
      request: { body: "PRIVATE_PROMPT", headers: { "authorization" => "SECRET_REQUEST" } }
    })
    details = Ai::ApiErrorDetails.new(error)
    assert_includes details.message, "Invalid parameter [REDACTED]"
    assert_includes details.message, "code=invalid_value"
    assert_includes details.message, "request_id=req-diagnostic"
    %w[sk-private-key UNRELATED_RESPONSE SECRET_HEADER SECRET_REQUEST PRIVATE_PROMPT].each { |text| refute_includes details.message, text }
    assert_not details.retryable?
  end

  test "distinguishes transient HTTP failures from permanent requests" do
    [ 408, 409, 429, 500, 503 ].each do |status|
      assert Ai::ApiErrorDetails.new(Faraday::Error.new("error", status: status)).retryable?, status.to_s
    end
    [ 400, 401, 403, 404, 422 ].each do |status|
      assert_not Ai::ApiErrorDetails.new(Faraday::Error.new("error", status: status)).retryable?, status.to_s
    end
    assert Ai::ApiErrorDetails.new(Faraday::TimeoutError.new("timeout")).retryable?
  end

  test "handles JSON-string and non-JSON provider responses" do
    structured = Faraday::BadRequestError.new("HTTP 400", status: 400, body: '{"error":{"message":"Invalid size","code":"invalid_value"}}')
    assert_includes Ai::ApiErrorDetails.new(structured).message, "Invalid size"
    html = Faraday::ServerError.new("HTTP 502", status: 502, body: "<html>private server response</html>")
    assert_equal "HTTP 502", Ai::ApiErrorDetails.new(html).message
  end
end
