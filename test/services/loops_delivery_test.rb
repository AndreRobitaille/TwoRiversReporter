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
      http.expect(:request, :ok) do |request|
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
end
