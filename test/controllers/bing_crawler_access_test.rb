require "test_helper"
require_relative "../support/crawler_access_assertions"

class BingCrawlerAccessTest < ActionDispatch::IntegrationTest
  CRAWLERS = [
    { feed: :bing, agent: "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm) Chrome/131.0.0.0 Safari/537.36", ip: "157.55.39.12", prefix: "157.55.39.0/24" }
  ].freeze

  include CrawlerAccessAssertions

  # Fetch as Bingbot, 2026-10-03 16:51 UTC. The address is inside bingbot.json
  # (40.77.167.0/24). The user agent is Bing's Chrome-style token.
  FETCH_AS_BINGBOT_UA = "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm) Chrome/116.0.1938.76 Safari/537.36"
  FETCH_AS_BINGBOT_IP = "40.77.167.27"

  test "fetch as bingbot with a star accept still reads the meeting and topic" do
    write_bing_prefix("40.77.167.0/24")

    [
      { "Accept" => "*/*" },
      { "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" },
      {},
      { "Accept" => "*/*", "Accept-Encoding" => "gzip, br" }
    ].each do |headers|
      [ meeting_path(@meeting), topic_path(@topic) ].each do |path|
        get path, headers: bing_headers(headers), env: { "SERVER_PROTOCOL" => "HTTP/2.0" }
        assert_response :success, headers.inspect
        assert_includes response.body, CrawlerAccessAssertions::WITHHELD
        assert_not_includes response.body, "Sign in to keep reading"
      end
    end

    get meeting_path(@meeting), headers: bing_headers("Accept" => "*/*"), env: { "SERVER_PROTOCOL" => "HTTP/2.0" }
    assert_equal "*/*", request.format.to_s
  end

  test "the same bingbot user agent on an unpublished address stays anonymous and logs only the reason" do
    write_bing_prefix("40.77.167.0/24")
    messages = []
    Rails.logger.stub(:info, ->(message = nil, &block) { messages << (message || block&.call).to_s }) do
      get meeting_path(@meeting), headers: bing_headers("Accept" => "*/*", "REMOTE_ADDR" => "198.51.100.9")
    end
    assert_response :success
    assert_not_includes response.body, CrawlerAccessAssertions::WITHHELD
    assert_includes response.body, "Sign in to keep reading"
    line = messages.find { |message| message.include?("Crawler verification rejected") }
    assert_equal "Crawler verification rejected ip=198.51.100.9 reason=ranges_miss", line
    assert_not_includes line, FETCH_AS_BINGBOT_UA
  end

  test "a verified star accept does not log a rejection" do
    write_bing_prefix("40.77.167.0/24")
    messages = []
    Rails.logger.stub(:info, ->(message = nil, &block) { messages << (message || block&.call).to_s }) do
      get meeting_path(@meeting), headers: bing_headers("Accept" => "*/*")
    end
    assert_includes response.body, CrawlerAccessAssertions::WITHHELD
    assert_empty messages.grep(/Crawler verification rejected/)
  end

  test "an explicit non html format stays gated and logs format" do
    write_bing_prefix("40.77.167.0/24")
    messages = []
    Rails.logger.stub(:info, ->(message = nil, &block) { messages << (message || block&.call).to_s }) do
      get topics_path(format: :turbo_stream), headers: bing_headers({})
    end
    assert_response :success
    assert_empty response.body.strip
    assert_equal "Crawler verification rejected ip=#{FETCH_AS_BINGBOT_IP} reason=format", messages.find { |message| message.include?("Crawler verification rejected") }
  end

  test "googlebot stays verified for html and star accepts" do
    Rails.cache.write(Crawlers::IpRanges.new.cache_key(:google), {
      prefixes: [ "66.249.66.0/24" ], fetched_at: Time.current.to_i
    })
    headers = {
      "User-Agent" => "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
      "REMOTE_ADDR" => "66.249.66.1"
    }
    [ "*/*", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" ].each do |accept|
      get meeting_path(@meeting), headers: headers.merge("Accept" => accept)
      assert_response :success
      assert_includes response.body, CrawlerAccessAssertions::WITHHELD
    end
  end

  private

    def write_bing_prefix(prefix)
      Rails.cache.write(Crawlers::IpRanges.new.cache_key(:bing), {
        prefixes: [ prefix ], fetched_at: Time.current.to_i
      })
    end

    def bing_headers(extra)
      { "User-Agent" => FETCH_AS_BINGBOT_UA, "REMOTE_ADDR" => FETCH_AS_BINGBOT_IP }.merge(extra)
    end
end
