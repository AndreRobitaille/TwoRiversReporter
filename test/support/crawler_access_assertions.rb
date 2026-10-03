require "minitest/mock"

module CrawlerAccessAssertions
  extend ActiveSupport::Concern

  WITHHELD = "CRAWLER_ONLY_EVIDENCE_CANARY".freeze

  included do
    setup do
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      crawler_cases.each do |crawler|
        Rails.cache.write(Crawlers::IpRanges.new.cache_key(crawler.fetch(:feed)), {
          prefixes: [ crawler.fetch(:prefix) ], fetched_at: Time.current.to_i
        })
      end
      @topic = Topic.create!(name: "Crawler Evidence", status: "approved")
      @topic.create_topic_briefing!(
        generation_tier: "full", headline: "The council discussed the creek project",
        editorial_content: WITHHELD,
        generation_data: { "editorial_analysis" => { "current_state" => WITHHELD } }
      )
      @meeting = Meeting.create!(body_name: "Crawler Council", starts_at: 3.days.ago, detail_page_url: "https://example.com/crawler-meeting")
      @meeting.meeting_summaries.create!(summary_type: "minutes_recap", content: "The council resolved #{WITHHELD}.")
    end

    teardown do
      Rails.cache = @original_cache
    end

    test "verified crawlers read full topic and meeting reporting without creating an account or session" do
      crawler_cases.each do |crawler|
        assert_no_difference([ "User.count", "Session.count" ]) do
          [ topic_path(@topic), meeting_path(@meeting) ].each do |path|
            get path, headers: crawler_headers(crawler)
            assert_response :success
            assert_includes response.body, WITHHELD
            assert_not @controller.send(:authenticated?)
            assert_not_includes response.body, "Sign in to keep reading"
            assert_includes response.headers["Cache-Control"], "no-store"
            data = json_ld_nodes.find { |node| node["@type"] == "WebPage" }
            assert_equal false, data.fetch("isAccessibleForFree")
            part = data.fetch("hasPart")
            assert_equal "WebPageElement", part.fetch("@type")
            assert_equal false, part.fetch("isAccessibleForFree")
            assert_equal ".gated-content", part.fetch("cssSelector")
            assert_select ".gated-content"
            assert_not_includes data.to_json, WITHHELD
          end
        end
      end
    end

    test "spoofed crawler names receive teasers with no canary in HTML metadata or attributes" do
      crawler_cases.each do |crawler|
        [ topic_path(@topic), meeting_path(@meeting) ].each do |path|
          get path, headers: crawler_headers(crawler, address: "198.51.100.42")
          assert_response :success
          assert_not_includes response.body, WITHHELD
          assert_includes response.body, "Sign in to keep reading"
          assert_select ".gated-content", count: 0
        end
      end
    end

    test "ordinary browser on a crawler network does not qualify" do
      crawler_cases.each do |crawler|
        get topic_path(@topic), headers: crawler_headers(crawler).merge("User-Agent" => "Mozilla/5.0")
        assert_response :success
        assert_not_includes response.body, WITHHELD
      end
    end

    test "browser cannot inject a crawler IP into forwarding headers" do
      crawler_cases.each do |crawler|
        [ { "REMOTE_ADDR" => "198.51.100.42", "X-Forwarded-For" => crawler.fetch(:ip) },
          { "REMOTE_ADDR" => "127.0.0.1", "X-Forwarded-For" => "#{crawler.fetch(:ip)}, 198.51.100.42, 172.18.0.3" } ].each do |overrides|
          get topic_path(@topic), headers: crawler_headers(crawler).merge(overrides)
          assert_response :success
          assert_not_includes response.body, WITHHELD
        end
      end
    end

    test "crawler traffic can pass through the configured proxy chain" do
      crawler_cases.each do |crawler|
        headers = crawler_headers(crawler, address: "127.0.0.1").merge("X-Forwarded-For" => "#{crawler.fetch(:ip)}, 172.18.0.3")
        get topic_path(@topic), headers: headers
        assert_response :success
        assert_includes response.body, WITHHELD
      end
    end

    test "crawler response cannot be reused as a human response" do
      crawler_cases.each do |crawler|
        get topic_path(@topic), headers: crawler_headers(crawler)
        assert_includes response.body, WITHHELD
        etag = response.headers["ETag"]

        get topic_path(@topic), headers: { "If-None-Match" => etag, "REMOTE_ADDR" => "198.51.100.42" }.compact
        assert_response :success
        assert_not_includes response.body, WITHHELD
        assert_includes response.headers["Cache-Control"], "no-store"
      end
    end

    test "missing verification ranges keep every crawler gated" do
      Rails.cache.clear
      Net::HTTP.stub(:start, ->(*) { flunk "page requests must not fetch crawler ranges" }) do
        crawler_cases.each do |crawler|
          get topic_path(@topic), headers: crawler_headers(crawler)
          assert_response :success
          assert_not_includes response.body, WITHHELD
        end
      end
    end

    test "public permission is reevaluated for every request and cannot be enabled by parameters" do
      get topic_path(@topic, bot: crawler_cases.first.fetch(:agent), verified_crawler: true)
      assert_response :success
      assert_not_includes response.body, WITHHELD

      get about_path, headers: crawler_headers(crawler_cases.first)
      assert_response :success
      assert @controller.send(:gated_for_visitor?)
      assert_nil json_ld_nodes.find { |node| node["@type"] == "WebPage" }
    end

    test "open mode omits registration markup and preserves full anonymous access" do
      SiteSetting.first.update!(access_mode: "open")

      get topic_path(@topic)
      assert_response :success
      assert_includes response.body, WITHHELD
      assert_select ".gated-content", count: 0
      assert_nil json_ld_nodes.find { |node| node["@type"] == "WebPage" }
      assert json_ld_nodes.any? { |node| node["@type"] == "Organization" }
    end

    test "crawler access never grants admin or account access" do
      crawler_cases.each do |crawler|
        [ admin_root_path, "/admin/users", settings_security_path, settings_profile_path ].each do |path|
          get path, headers: crawler_headers(crawler)
          assert_redirected_to new_public_session_path
        end
      end
    end

    test "crawler permission does not expose non HTML representations" do
      crawler_cases.each do |crawler|
        get topics_path(format: :turbo_stream), headers: crawler_headers(crawler)
        assert_response :success
        assert_empty response.body.strip
        assert @controller.send(:gated_for_visitor?)
      end
    end
  end

  private

    def crawler_cases
      self.class::CRAWLERS
    end

    def crawler_headers(crawler, address: crawler.fetch(:ip))
      { "User-Agent" => crawler.fetch(:agent), "REMOTE_ADDR" => address }
    end

    def json_ld_nodes
      css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }
    end
end
