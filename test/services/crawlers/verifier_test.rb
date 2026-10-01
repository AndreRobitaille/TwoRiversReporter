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

  test "Bing and Google require their own feeds, even when both are available" do
    @cache.write(@ranges.cache_key(:bing), { prefixes: [ "198.51.100.0/24" ], fetched_at: Time.current.to_i })

    assert_equal "bingbot", @verifier.call(request_for("bingbot/2.0", address: "198.51.100.2"))
    assert_nil @verifier.call(request_for("bingbot/2.0"))
    assert_nil @verifier.call(request_for("Googlebot/2.1", address: "198.51.100.2"))
    assert_nil @verifier.call(request_for("BingPreview/1.0", address: "198.51.100.2"))
  end

  test "OpenAI search and user retrieval use separate official feeds and do not grant training access" do
    @cache.write(@ranges.cache_key(:openai_search), { prefixes: [ "198.51.100.0/25" ], fetched_at: Time.current.to_i })
    @cache.write(@ranges.cache_key(:openai_user), { prefixes: [ "198.51.100.128/25" ], fetched_at: Time.current.to_i })

    assert_equal "OAI-SearchBot", @verifier.call(request_for("OAI-SearchBot/1.4", address: "198.51.100.2"))
    assert_equal "ChatGPT-User", @verifier.call(request_for("ChatGPT-User/1.0", address: "198.51.100.130"))
    assert_nil @verifier.call(request_for("ChatGPT-User/1.0", address: "198.51.100.2"))
    assert_nil @verifier.call(request_for("OAI-SearchBot/1.4", address: "198.51.100.130"))
    assert_nil @verifier.call(request_for("GPTBot/1.4", address: "198.51.100.2"))
    assert_nil @verifier.call(request_for("FakeChatGPT-User/1.0", address: "198.51.100.130"))
  end

  test "Anthropic's published feed permits search and user retrieval without granting training access" do
    @cache.write(@ranges.cache_key(:anthropic), { prefixes: [ "198.51.100.0/24" ], fetched_at: Time.current.to_i })

    assert_equal "Claude-SearchBot", @verifier.call(request_for("Claude-SearchBot/1.0", address: "198.51.100.2"))
    assert_equal "Claude-User", @verifier.call(request_for("Claude-User/1.0", address: "198.51.100.2"))
    assert_nil @verifier.call(request_for("ClaudeBot/1.0", address: "198.51.100.2"))
    assert_nil @verifier.call(request_for("Claude-User/1.0"))
    assert_nil @verifier.call(request_for("FakeClaude-User/1.0", address: "198.51.100.2"))
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
