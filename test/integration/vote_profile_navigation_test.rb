require "test_helper"

class VoteProfileNavigationTest < ActionDispatch::IntegrationTest
  setup do
    @member = Member.create!(name: "Jordan Navigation")
    @topic = Topic.create!(name: "crosswalk improvements", status: "approved", resident_impact_score: 5)
    @meeting = Meeting.create!(body_name: "City Council", starts_at: 1.day.ago,
      detail_page_url: "https://example.com/vote-profile")
    item = @meeting.agenda_items.create!(title: "Crosswalk improvements", kind: "item")
    AgendaItemTopic.create!(topic: @topic, agenda_item: item)
    motion = @meeting.motions.create!(agenda_item: item, description: "Approve crosswalk improvements", outcome: "passed")
    motion.votes.create!(member: @member, value: "yes")
    @meeting.meeting_summaries.create!(summary_type: "minutes_recap", generation_data: {
      "headline" => "Council considers crosswalk safety", "item_details" => [
        { "agenda_item_id" => item.id, "agenda_item_title" => item.title, "summary" => "Approved the improvements." }
      ]
    })
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(Crawlers::IpRanges.new.cache_key(:google), {
      prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i
    })
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "open readers follow voter identity to a profile and back to the same record" do
    assert_vote_links
    get member_path(@member)
    assert_response :success
    assert_select "h1", text: @member.name
    assert_select ".member-topic-votes a[href=?]", meeting_path(@meeting)
    assert_select ".member-topic-name a[href=?]", topic_path(@topic)
  end

  test "verified crawlers and members get vote links while anonymous and spoofed requests keep votes withheld" do
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    google = { "HTTP_USER_AGENT" => "Googlebot", "REMOTE_ADDR" => "66.249.66.1" }
    assert_vote_links(headers: google)

    [ {}, google.merge("REMOTE_ADDR" => "198.51.100.42") ].each do |headers|
      [ meeting_path(@meeting), topic_path(@topic) ].each do |path|
        get path, headers: headers
        assert_response :success
        assert_select "a[href=?]", member_path(@member), count: 0
        assert_not_includes response.body, @member.name
      end
    end

    sign_in_as(User.create!(email_address: "vote-profile@example.com", status: "active"))
    assert_vote_links
  end

  private

    def assert_vote_links(headers: {})
      { meeting_path(@meeting) => ".meeting-vote-list", topic_path(@topic) => ".votes-grid" }.each do |path, selector|
        get path, headers: headers
        assert_response :success
        assert_select "#{selector} a[href=?]", member_path(@member), text: @member.name, count: 1
        assert_not_includes response.parsed_body.at("head").to_html, @member.name
      end
    end
end
