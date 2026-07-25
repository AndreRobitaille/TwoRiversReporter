require "test_helper"

class MembersShowGatingTest < ActionDispatch::IntegrationTest
  WITHHELD_TOPIC = "Shoreline Setback Variance".freeze

  setup do
    @member = Member.create!(name: "Jordan Reyes")
    @committee = Committee.create!(name: "Plan Commission", committee_type: "city", status: "active")
    meeting = Meeting.create!(body_name: "Plan Commission Meeting", starts_at: 6.days.ago, committee: @committee,
      detail_page_url: "https://example.com/meetings/plan-commission")
    topic = Topic.create!(name: WITHHELD_TOPIC, status: "approved", canonical_name: WITHHELD_TOPIC,
      resident_impact_score: 3)
    item = meeting.agenda_items.create!(title: "Variance request", order_index: 1)
    item.agenda_item_topics.create!(topic: topic)
    motion = meeting.motions.create!(description: "Approve the variance", outcome: "passed", agenda_item: item)
    motion.votes.create!(member: @member, value: "yes")
  end

  test "anonymous visitor sees the heading but no votes" do
    set_access_mode("gated")

    get member_path(@member)

    assert_response :success
    assert_match(/Voting Record/, response.body)
    assert_no_match(/#{Regexp.escape(WITHHELD_TOPIC)}/i, response.body)
    assert_match(/Sign in to keep reading/, response.body)
  end

  test "signed-in member sees the voting record" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "member-reader@example.com", status: "active"))

    get member_path(@member)

    assert_match(/#{Regexp.escape(WITHHELD_TOPIC)}/i, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
