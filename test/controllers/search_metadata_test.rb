require "test_helper"

class SearchMetadataTest < ActionDispatch::IntegrationTest
  setup do
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(Crawlers::IpRanges.new.cache_key(:google), {
      prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i
    })
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "archive navigation exposes only public meeting facts and never bypasses the destination gate" do
    meeting = Meeting.create!(body_name: "Archive Council", starts_at: 2.months.ago,
      detail_page_url: "https://example.com/archive-gate")
    meeting.meeting_summaries.create!(summary_type: "minutes_recap",
      content: ("Opening context for the meeting. " * 20) + "ARCHIVE_WITHHELD_REPORTING_CANARY")
    archive_month = meeting_archive_month_path(year: meeting.starts_at.year, month: meeting.starts_at.strftime("%m"))

    get meeting_path(meeting), headers: google_headers
    assert_response :success
    assert_includes response.body, "ARCHIVE_WITHHELD_REPORTING_CANARY"

    [ {}, google_headers.merge("REMOTE_ADDR" => "198.51.100.42"), google_headers ].each do |headers|
      [ meeting_archive_path, archive_month ].each do |path|
        get path, headers: headers
        assert_response :success
        assert_not_includes response.body, "Opening context for the meeting"
        assert_not_includes response.body, "ARCHIVE_WITHHELD_REPORTING_CANARY"
        assert_select "meta[name=description][content*='Two Rivers']"
      end
      assert_select ".meeting-archive-list a[href=?]", meeting_path(meeting)
    end

    [ {}, google_headers.merge("REMOTE_ADDR" => "198.51.100.42") ].each do |headers|
      get meeting_path(meeting), headers: headers
      assert_response :success
      assert_select "h1", text: /Archive Council/
      assert_not_includes response.body, "ARCHIVE_WITHHELD_REPORTING_CANARY"
      assert_includes response.headers["Cache-Control"], "no-store"
    end

    sign_in_as(User.create!(email_address: "archive-reader@example.com", status: "active"))
    get archive_month
    assert_select ".meeting-archive-list a[href=?]", meeting_path(meeting)
    assert_not_includes response.body, "ARCHIVE_WITHHELD_REPORTING_CANARY"
    get meeting_path(meeting)
    assert_includes response.body, "ARCHIVE_WITHHELD_REPORTING_CANARY"
  end

  test "public topic descriptions reach all snippet tags without disclosing the gated headline" do
    topic = Topic.create!(name: "sandy bay highlands", status: "approved",
      description: 'Drainage & PFAS monitoring near "Sandy Bay".')
    topic.create_topic_briefing!(generation_tier: "full", headline: "WITHHELD_ZQX_BRIEFING_HEADLINE",
      editorial_content: "WITHHELD_ZQX_STORY")

    get topic_path(topic), headers: google_headers
    assert_response :success
    assert_snippet "WITHHELD_ZQX_BRIEFING_HEADLINE"
    assert_includes response.body, "WITHHELD_ZQX_STORY"

    [ {}, google_headers.merge("REMOTE_ADDR" => "198.51.100.42") ].each do |headers|
      get topic_path(topic), headers: headers
      assert_response :success
      assert_snippet 'Sandy Bay Highlands in Two Rivers, WI — Drainage & PFAS monitoring near "Sandy Bay".'
      assert_select ".topic-article-dek", text: topic.description
      assert_select "h1", text: topic.name
      assert_not_includes response.body, "WITHHELD_ZQX_BRIEFING_HEADLINE"
      assert_not_includes response.body, "WITHHELD_ZQX_STORY"
      assert_includes response.headers["Cache-Control"], "no-store"
    end

    topic.update!(description: "Updated public drainage scope.")
    get topic_path(topic)
    assert_snippet "Sandy Bay Highlands in Two Rivers, WI — Updated public drainage scope."
  end

  test "topic snippets stay distinct and use the existing title casing when the description is absent" do
    topic = Topic.create!(name: "wppi energy agreement", status: "approved", description: "Wholesale power rates.")
    get topic_path(topic)
    assert_snippet "WPPI Energy Agreement in Two Rivers, WI — Wholesale power rates."

    topic.update!(description: nil)
    get topic_path(topic)
    assert_snippet "WPPI Energy Agreement in Two Rivers, WI — every city meeting where it's come up, every vote, and what's still unresolved."
  end

  test "open readers and approved members keep the existing briefing snippet" do
    topic = Topic.create!(name: "harbor drainage", status: "approved", description: "Public drainage scope.")
    topic.create_topic_briefing!(generation_tier: "full", headline: "The harbor drainage vote is scheduled.")
    sign_in_as(User.create!(email_address: "search-metadata@example.com", status: "active"))
    get topic_path(topic)
    assert_snippet "The harbor drainage vote is scheduled."

    cookies.delete(:session_id)
    SiteSetting.first.update!(access_mode: "open")
    get topic_path(topic)
    assert_snippet "The harbor drainage vote is scheduled."
  end

  test "official metadata uses the first displayed current membership and follows later membership changes" do
    member = Member.create!(name: "Jordan Metadata")
    commission = Committee.create!(name: "Plan Commission")
    membership = member.committee_memberships.create!(committee: commission, role: "chair",
      position_title: "Vice President", source: "official_roster")
    zoning_membership = member.committee_memberships.create!(committee: Committee.create!(name: "Zoning Board"), role: "member", source: "seeded")
    member.committee_memberships.create!(committee: Committee.create!(name: "Old Board"), role: "chair",
      ended_on: Date.yesterday, source: "seeded")
    member.committee_memberships.create!(committee: Committee.create!(name: "A Staff Board"), role: "staff", source: "seeded")
    member.committee_memberships.create!(committee: Committee.create!(name: "A Nonvoting Board"), role: "non_voting", source: "seeded")

    get member_path(member)
    assert_profile_title "Jordan Metadata — Plan Commission Vice President in Two Rivers, WI"
    assert_snippet "Jordan Metadata — Plan Commission Vice President — committee memberships, meeting attendance, and voting record in Two Rivers, WI"
    assert_select "h1", text: member.name
    assert_select ".member-committee-name", text: "Plan Commission"
    assert_select ".member-committee .badge", text: "Vice President"

    membership.update!(ended_on: Date.current)
    get member_path(member)
    assert_profile_title "Jordan Metadata — Zoning Board Member in Two Rivers, WI"

    zoning_membership.update!(ended_on: Date.current)
    get member_path(member)
    assert_profile_title "Jordan Metadata — Committee Member in Two Rivers, WI"
  end

  test "current office takes precedence over committee roles and expires on the next request" do
    member = Member.create!(name: "Taylor Metadata")
    member.committee_memberships.create!(committee: Committee.create!(name: "Advisory Board"), role: "chair", source: "seeded")
    council = member.committee_memberships.create!(committee: Committee.create!(name: "City Council"), role: "member", source: "official_roster")
    position = member.member_positions.create!(kind: "city_council", title: "City Council President", source: "official_website",
      source_url: "https://example.com/council", verified_at: Time.current)

    get member_path(member)
    assert_profile_title "Taylor Metadata — City Council President in Two Rivers, WI"

    position.update!(ended_on: Date.current)
    get member_path(member)
    assert_profile_title "Taylor Metadata — City Council Member in Two Rivers, WI"

    council.update!(ended_on: Date.current)
    get member_path(member)
    assert_profile_title "Taylor Metadata — Advisory Board Chair in Two Rivers, WI"
  end

  test "home names the website at the canonical origin and organization links the confirmed profile" do
    host! "178.156.250.235"
    get root_path, params: { utm_source: "test" }
    assert_response :success
    websites = json_ld_nodes.select { |node| node["@type"] == "WebSite" }
    assert_equal [ {
      "@context" => "https://schema.org", "@type" => "WebSite",
      "name" => "Two Rivers Matters", "url" => "https://tworiversmatters.com/"
    } ], websites
    assert_equal [ "https://www.facebook.com/TwoRiversMatters" ],
      json_ld_nodes.find { |node| node["@type"] == "Organization" }.fetch("sameAs")
    assert_select "h1", text: "What's Happening"

    get about_path
    assert_nil json_ld_nodes.find { |node| node["@type"] == "WebSite" }
    assert_select "h1", text: /Your City Hall/
  ensure
    host! "www.example.com"
  end

  test "meeting pages omit incomplete event data for every audience even with a stored venue" do
    meeting = Meeting.create!(body_name: "Metadata Commission Meeting", starts_at: 2.days.from_now,
      location: "Council Chambers", detail_page_url: "https://example.com/metadata-meeting")
    [ {}, google_headers ].each do |headers|
      get meeting_path(meeting), headers: headers
      assert_response :success
      assert_nil json_ld_nodes.find { |node| node["@type"] == "Event" }
      assert_select "time.meeting-article-date[datetime=?]", meeting.starts_at.iso8601
      assert_select "h1", text: "Metadata Commission"
    end

    SiteSetting.first.update!(access_mode: "open")
    meeting.update!(location: nil)
    get meeting_path(meeting)
    assert_response :success
    assert_nil json_ld_nodes.find { |node| node["@type"] == "Event" }
  end

  private

    def google_headers
      { "User-Agent" => "Googlebot/2.1", "REMOTE_ADDR" => "66.249.66.1" }
    end

    def assert_snippet(expected)
      [ "meta[name='description']", "meta[property='og:description']", "meta[name='twitter:description']" ].each do |selector|
        assert_select selector, count: 1 do |nodes|
          assert_equal expected, nodes.first["content"]
        end
      end
    end

    def assert_profile_title(expected)
      assert_select "title", text: expected
      assert_select "meta[property='og:title'][content=?]", expected
      assert_select "meta[name='twitter:title'][content=?]", expected
    end

    def json_ld_nodes
      css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }
    end
end
