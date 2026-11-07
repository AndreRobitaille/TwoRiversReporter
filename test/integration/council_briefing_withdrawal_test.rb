require "test_helper"
require_relative "../support/briefing_withdrawal_scenario"

class CouncilBriefingWithdrawalTest < ActionDispatch::IntegrationTest
  include BriefingWithdrawalScenario

  setup do
    SiteSetting.instance.update!(access_mode: "open")
    build_withdrawal_scenario
    @reader = User.create!(email_address: "withdrawal-reader@example.test", status: "active")
    _, secret = ApiAccessToken.issue!(user: @reader, name: "Synthetic reader", expires_in: 90.days)
    @bearer = { "Authorization" => "Bearer #{secret}" }
    @illustration = @topic.generated_images.create!(status: "ready", purpose: "feature_and_og", source_briefing: @briefing)
    @illustration.file.attach(io: File.open(Rails.root.join("public/icon.png")), filename: "synthetic.png", content_type: "image/png")
  end

  test "identity correction withdraws stored briefing across resident representations without deleting evidence" do
    retained = @briefing.attributes
    other_retained = @other_briefing.attributes
    without_paid_providers do
      assert_public_claims
      get topic_path(@topic)
      etag = response.headers.fetch("ETag")
      before_correction = Time.current
      travel 2.seconds do
        withdraw_decision
        get topic_path(@topic), headers: { "If-None-Match" => etag }
        assert_response :success
        refute_includes response.body, STORY
        assert_withdrawn_claims
        get "/api/v1/topics", params: { updated_since: before_correction.iso8601(6) }, headers: @bearer
        assert_equal [ @topic.id ], response.parsed_body.fetch("data").map { |row| row["id"] }
      end
    end
    assert_equal retained.slice("headline", "editorial_content", "record_content", "generation_data"),
      @briefing.reload.attributes.slice("headline", "editorial_content", "record_content", "generation_data")
    assert_equal other_retained, @other_briefing.reload.attributes
    assert_equal "passed", @meeting.motions.sole.outcome
    assert_equal "yes", @meeting.motions.sole.votes.sole.value
    assert_equal @event.decision_observation_id, TopicStatusEvent.find(@event.id).decision_observation_id
    assert @document.source_versions.sole.file.attached?
  end

  test "gated signed in and anonymous responses cannot revive withdrawn analysis" do
    SiteSetting.instance.update!(access_mode: "gated")
    sign_in_as(@reader)
    get topic_path(@topic)
    assert_includes response.body, STORY
    withdraw_decision
    [ false, true ].each do |anonymous|
      cookies.delete(:session_id) if anonymous
      get topic_path(@topic)
      assert_response :success
      refute_includes response.body, STORY
      refute_includes response.body, CLAIM
      assert_includes response.headers["Cache-Control"], "no-store"
    end
    get "/api/v1/topics/#{@topic.id}", headers: @bearer
    assert_nil response.parsed_body.dig("data", "briefing")
  end

  test "verified crawler receives current reporting then loses the corrected briefing" do
    SiteSetting.instance.update!(access_mode: "gated")
    old_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(Crawlers::IpRanges.new.cache_key(:google), { prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i })
    headers = { "User-Agent" => "Googlebot/2.1", "REMOTE_ADDR" => "66.249.66.1" }
    without_paid_providers do
      get topic_path(@topic), headers: headers
      assert_includes response.body, STORY
      withdraw_decision
      get topic_path(@topic), headers: headers
      assert_response :success
      refute_includes response.body, STORY
      refute_includes response.body, CLAIM
      assert_select "h1", text: @topic.name
      head topic_path(@topic), headers: headers
      assert_response :success
      assert_includes response.headers["Cache-Control"], "no-store"
    end
  ensure
    Rails.cache = old_cache
  end

  private

  def assert_public_claims
    [ root_path, topics_path, topic_path(@topic), committee_path(@committee.slug) ].each do |path|
      get path
      assert_response :success
      assert_includes response.body, CLAIM, path
    end
    get topic_path(@topic)
    assert_includes response.body, STORY
    assert_select ".topic-feature-image img", count: 1
    [ {}, { "Accept" => "text/vnd.turbo-stream.html" } ].each do |headers|
      get topics_path, params: { q: CLAIM }, headers: headers
      assert_response :success
      assert_select "a[href='#{topic_path(@topic)}']", count: 1
    end
    get "/api/v1/topics/#{@topic.id}", headers: @bearer
    assert_equal STORY, response.parsed_body.dig("data", "briefing", "current_state")
    assert_not_nil response.parsed_body.dig("data", "illustration")
    get "/api/v1/topics", params: { q: CLAIM }, headers: @bearer
    assert_equal [ @topic.id ], response.parsed_body.fetch("data").map { |row| row["id"] }
    get "/api/v1/topics/#{@topic.id}/appearances", headers: @bearer
    assert_equal 1, response.parsed_body.fetch("data").count { |row| row["kind"] == "timeline_event" }
  end

  def assert_withdrawn_claims
    [ root_path, topics_path, topic_path(@topic), committee_path(@committee.slug), meeting_path(@meeting) ].each do |path|
      get path
      assert_response :success
      refute_includes response.body, CLAIM, path
      refute_includes response.body, STORY, path
      refute_includes response.body, @actor.email_address
      refute_includes response.body, @correction.reason
    end
    get topic_path(@topic)
    assert_select "h1", text: @topic.name
    assert_select ".topic-feature-image img", count: 0
    assert_select "a[href='#{meeting_path(@meeting)}']"
    [ {}, { "Accept" => "text/vnd.turbo-stream.html" } ].each do |headers|
      get topics_path, params: { q: CLAIM }, headers: headers
      assert_response :success
      assert_select "a[href='#{topic_path(@topic)}']", count: 0
    end
    [ "/api/v1/home", "/api/v1/topics", "/api/v1/topics/#{@topic.id}", "/api/v1/topics/#{@topic.id}/appearances" ].each do |path|
      get path, headers: @bearer
      assert_response :success
      refute_includes response.body, CLAIM
      refute_includes response.body, STORY
      assert_equal "private, no-store", response.headers["Cache-Control"]
    end
    get "/api/v1/topics/#{@topic.id}", headers: @bearer
    assert_nil response.parsed_body.dig("data", "briefing")
    assert_nil response.parsed_body.dig("data", "illustration")
    assert_equal false, response.parsed_body.dig("data", "has_analysis")
    get "/api/v1/topics/#{@topic.id}/appearances", headers: @bearer
    assert_equal [ "agenda_appearance" ], response.parsed_body.fetch("data").map { |row| row["kind"] }
    [ CLAIM, STORY ].each do |query|
      get "/api/v1/topics", params: { q: query }, headers: @bearer
      assert_equal [], response.parsed_body.fetch("data")
    end
    get "/api/v1/topics/#{@other.id}", headers: @bearer
    assert_equal @other_briefing.headline, response.parsed_body.dig("data", "headline")
  end
end
