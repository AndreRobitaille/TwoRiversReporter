require "test_helper"

class GrokCrawlerAccessTest < ActionDispatch::IntegrationTest
  WITHHELD = "GROK_VERIFICATION_BOUNDARY_CANARY".freeze

  setup do
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ranges = Crawlers::IpRanges.new
    Crawlers::Providers::FEEDS.each_key do |feed|
      Rails.cache.write(ranges.cache_key(feed), { prefixes: [ "192.0.2.0/24" ], fetched_at: Time.current.to_i })
    end

    @topic = Topic.create!(name: "Grok Verification Boundary", status: "approved")
    @topic.create_topic_briefing!(
      generation_tier: "full", headline: "Council discussed the inlet funding project", editorial_content: WITHHELD,
      generation_data: { "editorial_analysis" => { "current_state" => WITHHELD } }
    )
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "unverified Grok identity claims stay gated even on a known crawler network" do
    # Prove this is real reporting which an authorized crawler can receive.
    get topic_path(@topic), headers: { "User-Agent" => "Googlebot/2.1", "REMOTE_ADDR" => "192.0.2.4" }
    assert_response :success
    assert_includes response.body, WITHHELD

    # These are representative claims, not documented xAI crawler identities.
    %w[Grok Grok-User/1.0 xAI-Grok/1.0 xAI-Web-Crawler/1.0].each do |agent|
      get topic_path(@topic), headers: { "User-Agent" => agent, "REMOTE_ADDR" => "192.0.2.4" }
      assert_response :success
      assert_not_includes response.body, WITHHELD
      assert_includes response.body, "Sign in to keep reading"
    end
  end

  test "a Grok claim cannot supply its own verification by header parameter or cache entry" do
    ranges = Crawlers::IpRanges.new
    Rails.cache.write(ranges.cache_key(:grok), { prefixes: [ "192.0.2.0/24" ], fetched_at: Time.current.to_i })

    get topic_path(@topic, crawler_provider: "grok", verified_crawler: true), headers: {
      "User-Agent" => "Grok-User/1.0", "REMOTE_ADDR" => "192.0.2.4",
      "X-Verified-Bot" => "true", "X-Crawler-Provider" => "grok"
    }

    assert_response :success
    assert_not_includes response.body, WITHHELD
    assert_not @controller.send(:authenticated?)
    assert_includes response.headers["Cache-Control"], "no-store"
  end
end
