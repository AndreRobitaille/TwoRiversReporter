require "test_helper"

class CrawlerProbesControllerTest < ActionDispatch::IntegrationTest
  setup do
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @probes = Crawlers::Probe.create_pair
    ranges = Crawlers::IpRanges.new
    Rails.cache.write(ranges.cache_key(:google), { prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i })
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "public probe is readable and records the actual peer without reporting or cookies" do
    messages = []
    Rails.logger.stub(:info, ->(message = nil, &block) { messages << (message || block&.call) }) do
      get crawler_probe_path(@probes.fetch("public").fetch(:token)), headers: {
        "User-Agent" => "Grok-User/1.0", "REMOTE_ADDR" => "203.0.113.8",
        "X-Forwarded-For" => "66.249.66.1"
      }
    end

    assert_response :success
    assert_includes response.body, @probes.fetch("public").fetch(:code)
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_nil response.headers["Set-Cookie"]
    event = messages.filter_map { |message| JSON.parse(message) rescue nil }.find { |entry| entry["event"] == "crawler_probe" }
    assert_equal "203.0.113.8", event.fetch("client_ip")
    assert_equal "Grok-User/1.0", event.fetch("user_agent")
    assert_equal true, event.fetch("full_access")
    assert_not_includes messages.join, @probes.fetch("public").fetch(:code)
  end

  test "gated probe reaches verified crawlers but withholds its code from humans and Grok claims" do
    probe = @probes.fetch("gated")
    path = crawler_probe_path(probe.fetch(:token))
    get path, headers: { "User-Agent" => "Googlebot/2.1", "REMOTE_ADDR" => "66.249.66.1" }
    assert_response :success
    assert_includes response.body, probe.fetch(:code)

    [ "Mozilla/5.0", "Grok-User/1.0", "Googlebot/2.1" ].each do |agent|
      get path, headers: { "User-Agent" => agent, "REMOTE_ADDR" => "203.0.113.8" }
      assert_response :success
      assert_not_includes response.body, probe.fetch(:code)
      assert_includes response.body, "Verification code withheld"
      assert_includes response.headers["Cache-Control"], "no-store"
    end
  end

  test "query parameters and alternate formats cannot reveal the gated code" do
    probe = @probes.fetch("gated")
    get crawler_probe_path(probe.fetch(:token), mode: "public", verified_crawler: true)
    assert_response :success
    assert_not_includes response.body, probe.fetch(:code)

    [ "json", "turbo_stream" ].each do |format|
      get crawler_probe_path(probe.fetch(:token), format: format), headers: {
        "User-Agent" => "Googlebot/2.1", "REMOTE_ADDR" => "66.249.66.1"
      }
      assert_response :not_acceptable
      assert_not_includes response.body, probe.fetch(:code)
    end
  end

  test "missing expired and corrupt probes return no content" do
    get crawler_probe_path("0" * 32)
    assert_response :not_found

    probe = @probes.fetch("gated")
    travel_to 49.hours.from_now do
      get crawler_probe_path(probe.fetch(:token))
      assert_response :not_found
    end

    Rails.cache.write(Crawlers::Probe.cache_key(probe.fetch(:token)), { mode: "public", code: probe.fetch(:code) })
    get crawler_probe_path(probe.fetch(:token))
    assert_response :not_found
  end

  test "open mode permits both probes" do
    SiteSetting.instance.update!(access_mode: "open")
    @probes.each_value do |probe|
      get crawler_probe_path(probe.fetch(:token))
      assert_response :success
      assert_includes response.body, probe.fetch(:code)
      assert_includes response.headers["Cache-Control"], "no-store"
    end
  end
end
