require "test_helper"

class LoopsDeliveryTest < ActiveSupport::TestCase
  test "raises in production without an api key" do
    ENV.delete("LOOPS_API_KEY")

    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_raises(LoopsDelivery::MissingApiKey) do
        LoopsDelivery.deliver_now(email: "a@example.com", transactional_id: "id", data_variables: {})
      end
    end
  end

  test "posts the expected payload and auth header" do
    ENV["LOOPS_API_KEY"] = "test-key"
    body = nil
    headers = nil

    Net::HTTP.stub(:start, ->(*args, &block) {
      http = Minitest::Mock.new
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      http.expect(:request, response) do |request|
        body = JSON.parse(request.body)
        headers = request.to_hash
        true
      end
      result = block.call(http)
      http.verify
      result
    }) do
      LoopsDelivery.deliver_now(email: "a@example.com", transactional_id: "id", data_variables: { foo: "bar" })
    end

    assert_equal({ "email" => "a@example.com", "transactionalId" => "id", "dataVariables" => { "foo" => "bar" } }, body)
    assert_equal ["Bearer test-key"], headers["authorization"]
  ensure
    ENV.delete("LOOPS_API_KEY")
  end

  test "raises on non-2xx responses" do
    ENV["LOOPS_API_KEY"] = "test-key"

    Net::HTTP.stub(:start, ->(*args, &block) {
      http = Minitest::Mock.new
      response = Net::HTTPServerError.new("1.1", "500", "Internal Server Error")
      http.expect(:request, response) { true }
      result = block.call(http)
      http.verify
      result
    }) do
      assert_raises(LoopsDelivery::DeliveryError) do
        LoopsDelivery.deliver_now(email: "a@example.com", transactional_id: "id", data_variables: {})
      end
    end
  ensure
    ENV.delete("LOOPS_API_KEY")
  end

  test "wraps network exceptions as delivery errors" do
    ENV["LOOPS_API_KEY"] = "test-key"

    Net::HTTP.stub(:start, ->(*args) { raise SocketError, "boom" }) do
      error = assert_raises(LoopsDelivery::DeliveryError) do
        LoopsDelivery.deliver_now(email: "a@example.com", transactional_id: "id", data_variables: {})
      end

      assert_match /unable to deliver/i, error.message
    end
  ensure
    ENV.delete("LOOPS_API_KEY")
  end
end
