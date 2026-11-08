require "test_helper"
require_relative "../support/peer_votes_setup"

class MemberPeerVotesTest < ActionDispatch::IntegrationTest
  include PeerVotesSetup

  setup { setup_peer_votes }

  test "inspectable fractions use common eligible yes no decisions and separate divided votes" do
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Comparisons must not generate AI" }) do
      get member_path(@member)
      assert_select "#peer-comparisons", text: /2 of 3.*0 of 1/m
      get compare_member_path(@member, peer_id: @peer.id, term: @period.period_key)
      assert_response :success
      assert_select ".member-comparison-result", text: "Same vote on 2 of 3 decisions."
      assert_equal [ @agree.id, @split.id, @both_no.id ].sort, compared_ids.sort
      assert_select "[data-comparison-motion=?]", @split.id, text: /Council: Failed · 1-1/
      %w[Abstain Recused Absent].each do |status|
        assert_select ".member-comparison-method", text: /#{status}/
      end
      assert_select ".member-comparison-method", text: /Not recorded/
      assert_select ".member-comparison-method", text: /Outside documented shared service/
      assert_select ".member-comparison-method", text: /Vote inferred from attendance/
      assert_select ".member-comparison-method", text: /Approve minutes.*Routine procedural motion/m
      refute_match(/majority|minority|independen|\d+%/i, css_select(".member-article").text)

      get compare_member_path(@member, peer_id: @peer.id, term: @period.period_key, subset: "divided")
      assert_select ".member-comparison-result", text: "Same vote on 0 of 1 decisions."
      assert_equal [ @split.id ], compared_ids
      assert_select "a[href=?]", member_path(@member, term: @period.period_key, anchor: "peer-comparisons")
    end
  end

  test "an amendment and final decision remain distinct while consent and topic links do not multiply votes" do
    item = @comparison_meeting.agenda_items.create!(title: "Bridge construction")
    amendment = comparison_motion("Amend bridge design to preserve the footpath", agenda_item: item, peer: "no")
    @agree.update!(agenda_item: item)
    2.times { |n| item.topics << Topic.create!(name: "Bridge amendment topic #{n}", status: "approved") }
    consent = comparison_motion("Approve consent agenda including three items", agenda_item: item)
    get compare_member_path(@member, peer_id: @peer.id)
    assert_select ".member-comparison-result", text: "Same vote on 2 of 4 decisions."
    assert_equal [ @agree.id, @split.id, @both_no.id, amendment.id ].sort, compared_ids.sort
    assert_select ".member-comparison-method", text: /#{Regexp.escape(consent.description)}.*Routine procedural motion/m
    amendment.update!(description: "Approve minutes as corrected")
    [ [ @member, @peer ], [ @peer, @member ] ].each do |member, peer|
      get compare_member_path(member, peer_id: peer.id)
      assert_select ".member-comparison-result", text: "Same vote on 2 of 3 decisions."
    end
  end

  test "ballot and service corrections recalculate both directions on later reads" do
    get compare_member_path(@member, peer_id: @peer.id)
    assert_select ".member-comparison-result", text: "Same vote on 2 of 3 decisions."
    @split.votes.find_by!(member: @peer).update!(value: "yes")
    get compare_member_path(@member, peer_id: @peer.id)
    assert_select ".member-comparison-result", text: "Same vote on 3 of 3 decisions."
    get compare_member_path(@peer, peer_id: @member.id)
    assert_select ".member-comparison-result", text: "Same vote on 3 of 3 decisions."
    @agree.votes.find_by!(member: @member).update!(value: "recused")
    get compare_member_path(@member, peer_id: @peer.id)
    assert_select ".member-comparison-result", text: "Same vote on 2 of 2 decisions."
    @peer_period.update!(started_on: "2025-06-03")
    get compare_member_path(@member, peer_id: @peer.id)
    assert_select ".member-comparison-result", text: "No comparable votes in this selection."
    assert_select "[data-comparison-motion]", count: 0
  end

  test "topic links and reimport cannot multiply decisions and ambiguous meeting copies stay out of fractions" do
    item = @comparison_meeting.agenda_items.create!(title: "Bridge decision")
    2.times { |n| item.topics << Topic.create!(name: "Bridge issue #{n}", status: "approved", resident_impact_score: 4) }
    @agree.update!(agenda_item: item)
    get compare_member_path(@member, peer_id: @peer.id)
    assert_select ".member-comparison-result", text: "Same vote on 2 of 3 decisions."
    description = @agree.description
    @agree.destroy!
    @agree = comparison_motion(description, agenda_item: item)
    get compare_member_path(@member, peer_id: @peer.id)
    assert_select ".member-comparison-result", text: "Same vote on 2 of 3 decisions."
    assert_includes compared_ids, @agree.id

    duplicate = council_meeting("2025-06-02", committee: nil)
    comparison_motion(description, meeting: duplicate)
    get compare_member_path(@member, peer_id: @peer.id)
    assert_select ".member-comparison-result", text: "No comparable votes in this selection."
    assert_select ".member-comparison-method", text: /multiple imported copies/
    assert_select "[data-comparison-motion]", count: 0
    get member_path(@member, votes: "all")
    assert_select ".member-recorded-motion", text: description, count: 2
  end

  test "gated HTML withholds fractions and evidence after proving the allowed content" do
    path = compare_member_path(@member, peer_id: @peer.id)
    get path
    assert_select ".member-comparison-result", text: "Same vote on 2 of 3 decisions."
    assert_includes response.body, @agree.description
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    get path
    assert_response :success
    assert_select ".member-comparison-result, [data-comparison-motion]", count: 0
    refute_includes response.body, @agree.description
    refute_includes response.body, @outside.description
    assert_equal "private, no-store", response.headers["Cache-Control"]
    get member_path(@member)
    assert_select "#peer-comparisons", count: 0
    get compare_member_path(@member, peer_id: @peer.id, format: :json)
    assert_response :not_acceptable
    refute_includes response.body, @agree.description
  end

  test "verified Google can follow comparison links while a spoofed identity cannot read the evidence" do
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(Crawlers::IpRanges.new.cache_key(:google),
      { prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i })
    headers = { "User-Agent" => "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
      "REMOTE_ADDR" => "66.249.66.1" }
    path = compare_member_path(@member, peer_id: @peer.id, term: @period.period_key)
    get member_path(@member), headers: headers
    assert_select "#peer-comparisons a[href=?]", path
    get path, headers: headers
    assert_select ".member-comparison-result", text: "Same vote on 2 of 3 decisions."
    assert_includes response.body, @agree.description
    assert_equal "private, no-store", response.headers["Cache-Control"]
    get path, headers: headers.merge("REMOTE_ADDR" => "198.51.100.42")
    assert_select ".member-comparison-result, [data-comparison-motion]", count: 0
    refute_includes response.body, @agree.description
    get compare_member_path(@member, peer_id: @peer.id, format: :turbo_stream), headers: headers
    assert_response :not_acceptable
    refute_includes response.body, @agree.description
  ensure
    Rails.cache = cache
  end

  private

  def compared_ids
    css_select("[data-comparison-motion]").map { |row| row["data-comparison-motion"].to_i }
  end
end
