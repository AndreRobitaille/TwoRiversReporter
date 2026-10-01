require "test_helper"
require "minitest/mock"

class Crawlers::VerifierTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    @ranges = Crawlers::IpRanges.new(cache: @cache)
    @cache.write(@ranges.cache_key(:google), { prefixes: [ "192.0.2.0/24" ], fetched_at: Time.current.to_i })
    @verifier = Crawlers::Verifier.new(ranges: @ranges)
  end

  test "exact Google tokens require a matching provider address" do
    assert_equal "Googlebot", @verifier.call(request_for("Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"))
    assert_equal "Google-InspectionTool", @verifier.call(request_for("Google-InspectionTool/1.0"))
    assert_nil @verifier.call(request_for("Googlebot/2.1", address: "198.51.100.2"))
  end

  test "ordinary unknown ambiguous and substring identities remain gated even on a matching IP" do
    [ "Mozilla/5.0", "FakeGooglebot/2.1", "Googlebot-Evil/2.1", "Googlebot/2.1 Google-InspectionTool/1.0",
      "GoogleOther", "Googlebot-Image/1.0", "", "x" * 2049 ].each do |agent|
      assert_nil @verifier.call(request_for(agent)), agent
    end
    assert_nil @verifier.call(request_for("Googlebot/2.1 \xFF".b))
  end

  test "only read requests can qualify" do
    assert_equal "Googlebot", @verifier.call(request_for("Googlebot/2.1", method: "HEAD"))
    %w[POST PUT PATCH DELETE OPTIONS].each do |method|
      assert_nil @verifier.call(request_for("Googlebot/2.1", method: method))
    end
  end

  private

    def request_for(agent, address: "192.0.2.4", method: "GET")
      ActionDispatch::TestRequest.create.tap do |request|
        request.set_header("REMOTE_ADDR", address)
        request.set_header("HTTP_USER_AGENT", agent)
        request.set_header("REQUEST_METHOD", method)
      end
    end
end
