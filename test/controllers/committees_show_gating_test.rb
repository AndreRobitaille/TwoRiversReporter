require "test_helper"

class CommitteesShowGatingTest < ActionDispatch::IntegrationTest
  WITHHELD = "Harbor dredging permit renewal".freeze
  MEMBER_NAME = "Dana Harbor".freeze

  setup do
    @committee = Committee.create!(name: "Harbor Commission", committee_type: "city", status: "active")
    @member = Member.create!(name: MEMBER_NAME)
    CommitteeMembership.create!(committee: @committee, member: @member, role: "chair", source: "admin_manual")
    topic = Topic.create!(name: WITHHELD, status: "approved", canonical_name: WITHHELD)
    meeting = Meeting.create!(body_name: "Harbor Commission Meeting", starts_at: 5.days.ago, committee: @committee,
      detail_page_url: "https://example.com/meetings/harbor-commission")
    item = meeting.agenda_items.create!(title: "Dredging permit", order_index: 1)
    item.agenda_item_topics.create!(topic: topic)
  end

  test "anonymous visitor sees both headings but no member or activity content, then the gate" do
    set_access_mode("gated")

    get committee_path(@committee.slug)

    assert_response :success
    assert_match(/Current Members/, response.body)
    assert_match(/What They&#39;ve Been Working On|What They've Been Working On/, response.body)
    assert_no_match(/#{Regexp.escape(MEMBER_NAME)}/i, response.body)
    assert_no_match(/#{Regexp.escape(WITHHELD)}/i, response.body)
    assert_select ".gate-card"
    assert_match(/Sign in to keep reading/, response.body)

    # The gate renders once, after both empty headings — not one per section.
    assert_select ".gate-card", count: 1
  end

  test "signed-in member sees members and activity as before" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "committee-reader@example.com", status: "active"))

    get committee_path(@committee.slug)

    assert_response :success
    assert_match(/#{Regexp.escape(MEMBER_NAME)}/i, response.body)
    assert_match(/#{Regexp.escape(WITHHELD)}/i, response.body)
    assert_select ".gate-card", count: 0
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
