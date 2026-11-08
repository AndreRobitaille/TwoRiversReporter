require "test_helper"

class MemberRecordedVotesTest < ActionDispatch::IntegrationTest
  setup do
    @member = Member.create!(name: "Morgan Record")
    @meeting = Meeting.create!(body_name: "City Council", starts_at: Time.zone.local(2025, 5, 30, 11, 45),
      detail_page_url: "https://example.com/recorded-votes-source")
  end

  test "all recorded votes keeps procedural motions and distinct decisions under the same agenda item" do
    item = @meeting.agenda_items.create!(title: "Manager selection")
    2.times do |index|
      item.agenda_item_topics.create!(topic: Topic.create!(name: "selection topic #{index}", status: "approved", resident_impact_score: 4))
    end
    closed = record_vote("Enter closed session for interviews", agenda_item: item)
    negotiation = record_vote("Authorize negotiations, returning the proposed agreement for later Council action", agenda_item: item)
    abstention = record_vote("Accept the quarterly report", value: "abstain")
    recusal = record_vote("Award the maintenance contract", value: "recused")
    absent = record_vote("Approve the capital plan", value: "absent")

    Ai::OpenAiService.stub(:new, ->(*) { flunk "Reading saved votes must not call AI" }) do
      get member_path(@member)
      assert_select "a[href=?]", member_path(@member, votes: "all", anchor: "voting-record"), text: "All recorded votes"

      get member_path(@member, votes: "all")
      assert_response :success
      assert_select ".member-recorded-votes .member-vote-row", count: 5
      [ closed, negotiation, abstention, recusal, absent ].each do |vote|
        assert_select "#recorded-vote-#{vote.id}" do
          assert_select ".member-recorded-motion", text: vote.motion.description
          assert_select ".vote-value", text: vote.value.titleize
          assert_select "a[href=?]", meeting_path(@meeting), text: "Meeting and sources"
        end
      end
      assert_select ".member-recorded-coverage", count: 0

      negotiation.update!(value: "no")
      get member_path(@member, votes: "all")
      assert_select "#recorded-vote-#{negotiation.id} .vote-value", text: "No"
    end
  end

  test "pagination preserves the all-recorded view with stable ordering and no repeated rows" do
    votes = 26.times.map { |index| record_vote("Recorded decision #{index}") }

    get member_path(@member, votes: "all")
    assert_select ".member-vote-pages", count: 1
    assert_select ".member-vote-pages [aria-current=page]", text: "1"
    first_ids = css_select(".member-recorded-votes .member-vote-row").map { |row| row["id"] }
    assert_equal votes.reverse.first(25).map { |vote| "recorded-vote-#{vote.id}" }, first_ids
    assert_vote_page_link(2, all: true)

    get member_path(@member, votes: "all", page: 2)
    assert_select ".member-recorded-votes .member-vote-row", count: 1
    assert_select "#recorded-vote-#{votes.first.id}"
    assert_select ".member-vote-pages [aria-current=page]", text: "2"
    assert_vote_page_link(1, all: true)
    assert_select ".member-vote-pages a[href][rel=next]", count: 0

    get member_path(@member, votes: "all", page: 3)
    assert_response :success
    assert_select ".member-recorded-votes .member-vote-row", count: 0
    assert_select ".member-vote-pages", count: 0
    assert_select "a[href=?]", member_path(@member, votes: "all", anchor: "voting-record"), text: "Return to the newest votes"
  end

  test "featured pages retain older substantive votes and omit unanimously approved procedural votes" do
    votes = 26.times.map { |index| record_vote("Substantive decision #{index}") }
    votes.first.motion.update!(description: "Authorize negotiations following closed session")
    routine = record_vote("Accept consent agenda")
    routine.motion.votes.create!(member: Member.create!(name: "Absent member"), value: "absent")

    get member_path(@member)
    assert_select ".member-vote-row", count: 25
    assert_not_includes response.body, routine.motion.description
    assert_select ".member-vote-motion a", text: votes.first.motion.description, count: 0
    assert_vote_page_link(2)

    get member_path(@member, page: 2)
    assert_select ".member-vote-row", count: 1
    assert_includes response.body, votes.first.motion.description
    assert_select ".member-vote-views a[aria-current='page']", text: "Featured votes"
    assert_vote_page_link(1)

    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    get member_path(@member, page: 2)
    assert_not_includes response.body, votes.first.motion.description
    assert_select ".member-vote-pages", count: 0
  end

  test "featured procedural decisions use everyone's recorded vote even when linked to important topics" do
    item = @meeting.agenda_items.create!(title: "Manager selection")
    item.agenda_item_topics.create!(topic: Topic.create!(name: "manager search", status: "approved", resident_impact_score: 4))
    routine = record_vote("Convene in closed session for interviews", agenda_item: item)
    get member_path(@member)
    assert_select ".member-vote-row", count: 0

    other = Member.create!(name: "Other attending member")
    other_vote = routine.motion.votes.create!(member: other, value: "no")
    %w[no abstain recused].each do |value|
      other_vote.update!(value: value)
      get member_path(@member)
      assert_select ".member-vote-row", count: 1
      assert_includes response.body, routine.motion.description
    end

    other_vote.update!(value: "yes")
    get member_path(@member)
    assert_select ".member-vote-row", count: 0

    routine.update!(value: "no")
    other_vote.update!(value: "no")
    routine.motion.update!(outcome: "failed")
    get member_path(@member)
    assert_select ".member-vote-row", count: 1

    get member_path(@member, votes: "all")
    assert_select "#recorded-vote-#{routine.id}"
  end

  test "gated audience changes withhold the entire recorded list and later pages" do
    vote = record_vote("Authorize the distinctive harbor assessment")
    get member_path(@member, votes: "all")
    assert_includes response.body, vote.motion.description

    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    [ {}, { page: 2 }, { format: :json } ].each do |options|
      get member_path(@member, votes: "all", **options)
      assert_includes [ 200, 406 ], response.status
      assert_equal "private, no-store", response.headers["Cache-Control"] if response.status == 200
      assert_not_includes response.body, vote.motion.description
      assert_select ".member-recorded-votes, .member-vote-pages", count: 0 if response.status == 200
    end

    sign_in_as(User.create!(email_address: "recorded-votes-reader@example.com", status: "active"))
    get member_path(@member, votes: "all")
    assert_select ".gated-content #recorded-vote-#{vote.id}"

    delete public_session_path
    assert_redirected_to root_path
    get member_path(@member, votes: "all")
    assert_not_includes response.body, vote.motion.description
    assert_match(/Sign in to keep reading/, response.body)
  end

  test "a member with no recorded votes gets a clear empty state" do
    get member_path(@member, votes: "all")
    assert_response :success
    assert_select ".member-recorded-empty", text: /No votes have been recorded/
    assert_select ".member-recorded-coverage", count: 0
    assert_select ".member-vote-pages", count: 0
  end

  test "verified reporting crawler can read recorded votes in gated mode" do
    vote = record_vote("Approve the public pier repairs")
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(Crawlers::IpRanges.new.cache_key(:google), {
      prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i
    })

    get member_path(@member, votes: "all"), headers: { "HTTP_USER_AGENT" => "Googlebot", "REMOTE_ADDR" => "66.249.66.1" }
    assert_response :success
    assert_select ".gated-content #recorded-vote-#{vote.id}"
    assert_equal "private, no-store", response.headers["Cache-Control"]
  ensure
    Rails.cache = original_cache
  end

  private

    def assert_vote_page_link(page, all: false)
      assert_select ".member-vote-pages a[href]", text: page.to_s, count: 1 do |links|
        target = URI.parse(links.sole["href"])
        assert_equal member_path(@member), target.path
        expected = { "page" => page.to_s }
        expected["votes"] = "all" if all
        assert_equal expected, Rack::Utils.parse_query(target.query)
        assert_equal "voting-record", target.fragment
      end
    end

    def record_vote(description, value: "yes", agenda_item: nil)
      motion = @meeting.motions.create!(description: description, outcome: "passed", agenda_item: agenda_item)
      motion.votes.create!(member: @member, value: value)
    end
end
