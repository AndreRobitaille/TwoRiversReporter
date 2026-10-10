require "test_helper"
require Rails.root.join("db/migrate/20261003180000_add_legacy_wordpress_redirects")

class SeoMarkupTest < ActionDispatch::IntegrationTest
  setup do
    @starts_at = Time.zone.parse("2026-10-05 18:00:00")
    @meeting = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: @starts_at,
      location: "Council Chambers",
      detail_page_url: "https://www.two-rivers.org/meetings/secret-detail",
      status: "scheduled"
    )
    @topic = Topic.create!(name: "wppi energy contract", status: "approved")
  end

  test "home and about titles are the brand sentences, including social tags" do
    home = "Two Rivers Matters: Two Rivers, WI City Hall in Plain English"
    about = "About Two Rivers Matters: Two Rivers, WI City Hall in Plain English"

    get root_path
    assert_select "title", text: home
    assert_select "meta[property='og:title'][content='#{home}']"
    assert_select "meta[name='twitter:title'][content='#{about}']", count: 0
    assert_select "meta[name='twitter:title'][content='#{home}']"
    assert_select "h1", text: "What's Happening"

    get about_path
    assert_select "title", text: about
    assert_select "meta[property='og:title'][content='#{about}']"
    assert_select "meta[name='twitter:title'][content='#{about}']"
    assert_select "h1", text: /Your City Hall/
  end

  test "topic titles use title case while the H1 keeps the stored name" do
    get topic_path(@topic)
    assert_equal "wppi energy contract", @topic.name
    assert_select "h1.topic-article-title", text: "wppi energy contract"
    assert_select "title", text: "WPPI Energy Contract in Two Rivers, WI"

    acronym = Topic.create!(name: "WPPI power contract", status: "approved")
    get topic_path(acronym)
    assert_equal "wppi power contract", acronym.name
    assert_select "h1.topic-article-title", text: "wppi power contract"
    assert_select "title", text: "WPPI Power Contract in Two Rivers, WI"
    assert_select "meta[property='og:title'][content='WPPI Power Contract in Two Rivers, WI']"
    assert_select "meta[name='twitter:title'][content='WPPI Power Contract in Two Rivers, WI']"
  end

  test "a topic name containing a script tag is escaped in the title" do
    topic = Topic.create!(name: "lead pipes script", status: "approved")
    topic.update_column(:name, "lead pipes <script>")

    get topic_path(topic)

    assert_response :success
    assert_select "h1.topic-article-title", text: "lead pipes <script>"
    assert_select "title", text: "Lead Pipes <Script> in Two Rivers, WI"
    assert_includes response.body, "<title>Lead Pipes &lt;Script&gt; in Two Rivers, WI</title>"
    assert_includes response.body, 'property="og:title" content="Lead Pipes &lt;Script&gt; in Two Rivers, WI"'
    assert_includes response.body, 'name="twitter:title" content="Lead Pipes &lt;Script&gt; in Two Rivers, WI"'
  end

  test "canonical and open graph urls drop the query string" do
    get meeting_path(@meeting), params: { fbclid: "abc", utm_source: "x", page: "2" }

    canonical = "https://#{WwwRedirect::APEX_HOST}#{meeting_path(@meeting)}"
    assert_select "link[rel='canonical'][href='#{canonical}']"
    assert_select "meta[property='og:url'][content='#{canonical}']"
    assert_no_match(/fbclid|utm_source/, response.body[/<link rel="canonical"[^>]*>/])
  end

  test "explore is noindex" do
    get topics_explore_path
    assert_response :success
    assert_select "meta[name='robots'][content='noindex']"
  end

  test "missing meeting is a real 404 and a duplicate meeting is a permanent redirect" do
    get meeting_path(id: 9_999_999)
    assert_response :not_found
    assert_match(/doesn't exist/, response.body)

    duplicate = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: @starts_at,
      committee: Committee.create!(name: "City Council"),
      detail_page_url: "https://example.com/duplicate"
    )
    @meeting.update!(committee: duplicate.committee)
    canonical = Meeting.preferred_duplicate(@meeting.identity_matches)

    get meeting_path((@meeting.id == canonical.id) ? duplicate : @meeting)
    assert_response :moved_permanently
    assert_redirected_to meeting_url(canonical)
  end

  test "missing admin record still redirects with a flash" do
    admin = User.create!(email_address: "seo-admin@example.com", admin: true, status: "active")
    sign_in_as(admin)

    get "/admin/users/999999"

    assert_redirected_to root_path
    assert_equal "That record could not be found.", flash[:alert]
  end

  test "a non apex host still publishes apex canonical open graph and json ld urls" do
    set_access_mode("gated")
    host! "178.156.250.235"
    get meeting_path(@meeting), params: { fbclid: "abc", utm_source: "x" }

    apex = "https://#{WwwRedirect::APEX_HOST}#{meeting_path(@meeting)}"
    assert_select "link[rel='canonical'][href='#{apex}']"
    assert_select "meta[property='og:url'][content='#{apex}']"
    assert_no_match(/178\.156\.250\.235|fbclid|utm_source/, response.body[/<link rel="canonical"[^>]*>/])

    nodes = css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }
    assert_equal apex, nodes.find { |node| node["@type"] == "WebPage" }["url"]
    assert_equal apex, nodes.find { |node| node["@type"] == "Event" }["url"]
    assert_equal "https://#{WwwRedirect::APEX_HOST}/", nodes.find { |node| node["@type"] == "Organization" }["url"]
    assert_equal "https://#{WwwRedirect::APEX_HOST}/icon.png", nodes.find { |node| node["@type"] == "Organization" }["logo"]
  ensure
    host! "www.example.com"
  end

  test "www redirects to the apex and keeps the path and query" do
    host! "www.tworiversmatters.com"
    get "/meetings/#{@meeting.id}?utm_source=newsletter&fbclid=1"

    assert_response :moved_permanently
    assert_equal "https://tworiversmatters.com/meetings/#{@meeting.id}?utm_source=newsletter&fbclid=1", response.headers["Location"]
  ensure
    host! "www.example.com"
  end

  test "organization and meeting event markup use only stored fields" do
    set_access_mode("gated")
    get meeting_path(@meeting)

    nodes = css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }
    organization = nodes.find { |node| node["@type"] == "Organization" }
    event = nodes.find { |node| node["@type"] == "Event" }
    paywall = nodes.find { |node| node["@type"] == "WebPage" }

    assert_equal [ "@context", "@type", "description", "logo", "name", "url" ].sort, organization.keys.sort
    assert_equal "Two Rivers Matters", organization["name"]
    assert_equal "https://#{WwwRedirect::APEX_HOST}/", organization["url"]
    assert_equal "https://#{WwwRedirect::APEX_HOST}/icon.png", organization["logo"]
    assert_equal AccessHelper::DEFAULT_SITE_DESCRIPTION, organization["description"]

    assert_equal [ "@context", "@type", "eventStatus", "name", "startDate", "url" ].sort, event.keys.sort
    assert_equal "City Council", event["name"]
    assert_equal "https://schema.org/EventScheduled", event["eventStatus"]
    assert_equal @starts_at.iso8601, event["startDate"]
    assert_equal "https://#{WwwRedirect::APEX_HOST}#{meeting_path(@meeting)}", event["url"]
    assert_not_includes event.to_json, "two-rivers.org"
    assert_not_includes event.to_json, "Council Chambers"

    assert_equal ".gated-content", paywall.dig("hasPart", "cssSelector")
    assert_equal false, paywall.dig("hasPart", "isAccessibleForFree")
    assert_select ".gated-content", count: 0
    assert_select "time.meeting-article-date[datetime='#{@starts_at.iso8601}']"
  end

  test "a cancelled meeting event is marked cancelled" do
    @meeting.update!(status: "cancelled")
    get meeting_path(@meeting)
    event = css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }.find { |node| node["@type"] == "Event" }
    assert_equal "https://schema.org/EventCancelled", event["eventStatus"]
  end

  test "index paywall markup does not name a section that the page never renders" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "seo-index-member@example.com", status: "active"))

    [ root_path, topics_path, meetings_path ].each do |path|
      get path
      assert_response :success
      assert_select ".gated-content", count: 0
      paywall = css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }
        .find { |node| node["@type"] == "WebPage" }
      assert_equal false, paywall.fetch("isAccessibleForFree")
      assert_not paywall.key?("hasPart"), "#{path} advertises a selector with no matching section"
    end
  end

  test "legacy wordpress paths redirect once and do not overwrite an edited row" do
    migration = AddLegacyWordpressRedirects.new
    migration.up
    migration.up

    assert_equal AddLegacyWordpressRedirects::PATHS.size, Redirect.where(source_path: AddLegacyWordpressRedirects::PATHS.keys).count
    AddLegacyWordpressRedirects::PATHS.each do |source, destination|
      record = Redirect.find_by!(source_path: source)
      assert_equal 301, record.status_code
      assert_equal destination, record.destination
    end

    Redirect.find_by!(source_path: "/contact").update!(destination: "/topics")
    migration.up
    assert_equal "/topics", Redirect.find_by!(source_path: "/contact").destination

    get "/two-rivers-committees/"
    assert_response :moved_permanently
    assert_equal "/committees", response.headers["Location"]

    get "/airbnb-in-two-rivers/?ref=old#str-petition"
    assert_response :moved_permanently
    assert_equal "/topics/230", response.headers["Location"]

    get "/weekly-recap-jan-12-2025"
    assert_response :moved_permanently
    assert_equal "/meetings", response.headers["Location"]

    get "/city-council-meeting-apr-7-2025/"
    assert_response :moved_permanently
    assert_equal "/committees/city-council", response.headers["Location"]

    get "/contact/"
    assert_response :moved_permanently
    assert_equal "/topics", response.headers["Location"]
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
