require "test_helper"

class SitemapsControllerTest < ActionDispatch::IntegrationTest
  CRAWLERS = {
    google: [ "Googlebot", "Google-InspectionTool" ],
    bing: [ "bingbot" ],
    openai_search: [ "OAI-SearchBot" ],
    openai_user: [ "ChatGPT-User" ],
    anthropic: [ "Claude-SearchBot", "Claude-User" ]
  }.freeze

  setup do
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    CRAWLERS.each_key do |feed|
      Rails.cache.write(Crawlers::IpRanges.new.cache_key(feed), {
        prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i
      })
    end
    @approved_topic = Topic.create!(name: "downtown tif district", status: "approved", lifecycle_status: "active")
    @blocked_topic = Topic.create!(name: "infrastructure", status: "blocked", lifecycle_status: "active")
    @meeting = Meeting.create!(body_name: "City Council", starts_at: 1.day.ago, detail_page_url: "https://example.com/meetings/1")
    @member = Member.create!(name: "Public Member")
    @committee = Committee.create!(name: "City Council")
    @approved_topic.create_topic_briefing!(headline: "SITEMAP_REPORTING_CANARY", generation_tier: "full")
    @meeting.meeting_summaries.create!(summary_type: "minutes_recap", content: "SITEMAP_REPORTING_CANARY")
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "anonymous gated sitemap contains exactly the public overview pages" do
    get sitemap_path
    assert_response :success
    assert_equal "application/xml; charset=utf-8", response.content_type
    assert_equal [ root_url, about_url ], sitemap_urls
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "all seven verified crawler identities receive a full canonical catalog without reporting text" do
    CRAWLERS.values.flatten.each do |agent|
      get sitemap_path, headers: crawler_headers(agent)
      assert_full_catalog
    end
  end

  test "spoofed identities forwarded addresses and ordinary browsers cannot retrieve the catalog" do
    [ crawler_headers("Googlebot", address: "198.51.100.42"),
      crawler_headers("Mozilla/5.0"),
      crawler_headers("Googlebot", address: "198.51.100.42").merge("X-Forwarded-For" => "66.249.66.1"),
      crawler_headers("Googlebot", address: "127.0.0.1").merge("X-Forwarded-For" => "66.249.66.1, 198.51.100.42, 172.18.0.3"),
      crawler_headers("Grok"), crawler_headers("GPTBot"), crawler_headers("ClaudeBot") ].each do |headers|
      get sitemap_path, headers: headers
      assert_response :success
      assert_equal [ root_url, about_url ], sitemap_urls
    end
  end

  test "missing or expired verification keeps the sitemap limited" do
    Rails.cache.clear
    get sitemap_path, headers: crawler_headers("Googlebot")
    assert_equal [ root_url, about_url ], sitemap_urls

    Rails.cache.write(Crawlers::IpRanges.new.cache_key(:google), {
      prefixes: [ "66.249.66.0/27" ], fetched_at: 49.hours.ago.to_i
    })
    get sitemap_path, headers: crawler_headers("Googlebot")
    assert_equal [ root_url, about_url ], sitemap_urls
  end

  test "approved members receive the full catalog" do
    user = User.create!(email_address: "sitemap@example.com", status: "active")
    sign_in_as(user)
    get sitemap_path
    assert_full_catalog
  end

  test "open mode catalog is rebuilt and cannot be cached across a switch to gated" do
    SiteSetting.first.update!(access_mode: "open")
    get sitemap_path
    assert_full_catalog
    etag = response.headers["ETag"]
    new_topic = Topic.create!(name: "new automatic sitemap entry", status: "approved")
    get sitemap_path
    assert_includes sitemap_urls, topic_url(new_topic)

    SiteSetting.first.update!(access_mode: "gated")
    get sitemap_path, headers: { "If-None-Match" => etag }.compact
    assert_response :success
    assert_equal [ root_url, about_url ], sitemap_urls
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "crawler catalog is not reused for a human conditional request" do
    get sitemap_path, headers: crawler_headers("Googlebot")
    assert_full_catalog
    get sitemap_path, headers: { "If-None-Match" => response.headers["ETag"] }.compact
    assert_response :success
    assert_equal [ root_url, about_url ], sitemap_urls
  end

  test "only canonical meetings are advertised using the detail page cancellation and content precedence" do
    duplicate = Meeting.create!(body_name: @meeting.body_name, starts_at: @meeting.starts_at, detail_page_url: "https://example.com/duplicate")
    get sitemap_path, headers: crawler_headers("Googlebot")
    assert_includes sitemap_urls, meeting_url(@meeting)
    assert_not_includes sitemap_urls, meeting_url(duplicate)

    duplicate.update!(status: "cancelled")
    distinct = Meeting.create!(body_name: "Plan Commission", starts_at: @meeting.starts_at, detail_page_url: "https://example.com/distinct")
    get sitemap_path, headers: crawler_headers("Googlebot")
    assert_includes sitemap_urls, meeting_url(duplicate)
    assert_not_includes sitemap_urls, meeting_url(@meeting)
    assert_includes sitemap_urls, meeting_url(distinct)
  end

  test "lastmod follows regenerated briefing and summary updates rather than the meeting date" do
    @approved_topic.update_columns(updated_at: 5.days.ago, last_activity_at: 1.year.ago)
    @approved_topic.topic_briefing.update_columns(updated_at: 2.hours.ago)
    @meeting.update_columns(updated_at: 5.days.ago)
    @meeting.meeting_summaries.first.update_columns(updated_at: 1.hour.ago)

    get sitemap_path, headers: crawler_headers("Googlebot")
    assert_equal @approved_topic.topic_briefing.reload.updated_at.iso8601, lastmod_for(topic_url(@approved_topic))
    assert_equal @meeting.meeting_summaries.first.reload.updated_at.iso8601, lastmod_for(meeting_url(@meeting))
    assert_nil lastmod_for(member_url(@member))
    assert_nil lastmod_for(committee_url(@committee.slug))
  end

  test "dissolved committees and proposed or blocked topics are excluded even for a verified crawler" do
    dissolved = Committee.create!(name: "Former Commission", status: "dissolved")
    dormant = Committee.create!(name: "Dormant Commission", status: "dormant")
    proposed = Topic.create!(name: "unreviewed subject", status: "proposed")
    get sitemap_path, headers: crawler_headers("Googlebot")
    assert_full_catalog(extra_urls: [ committee_url(dormant.slug) ])
    assert_not_includes sitemap_urls, committee_url(dissolved.slug)
    assert_not_includes sitemap_urls, topic_url(proposed)
  end

  private

    def crawler_headers(agent, address: "66.249.66.1")
      { "User-Agent" => "SitemapTest #{agent}/1.0", "REMOTE_ADDR" => address }
    end

    def sitemap_document
      document = Nokogiri::XML(response.body) { |config| config.strict }
      document.remove_namespaces!
    end

    def sitemap_urls
      sitemap_document.xpath("//url/loc").map(&:text)
    end

    def lastmod_for(url)
      sitemap_document.xpath("//url").find { |node| node.at_xpath("loc").text == url }.at_xpath("lastmod")&.text
    end

    def assert_full_catalog(extra_urls: [])
      assert_response :success
      expected = [ root_url, about_url, topics_url, meetings_url, committees_url,
        topic_url(@approved_topic), meeting_url(@meeting), member_url(@member), committee_url(@committee.slug) ] + extra_urls
      assert_equal expected.sort, sitemap_urls.sort
      assert_not_includes response.body, "SITEMAP_REPORTING_CANARY"
      assert_includes response.headers["Cache-Control"], "no-store"
    end
end
