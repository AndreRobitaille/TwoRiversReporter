require "test_helper"

class CommitteesShowGatingTest < ActionDispatch::IntegrationTest
  WITHHELD = "Harbor dredging permit renewal".freeze

  setup do
    @committee = Committee.create!(name: "Harbor Commission", committee_type: "city", status: "active")
    topic = Topic.create!(name: WITHHELD, status: "approved", canonical_name: WITHHELD)
    meeting = Meeting.create!(body_name: "Harbor Commission Meeting", starts_at: 5.days.ago, committee: @committee,
      detail_page_url: "https://example.com/meetings/harbor-commission")
    item = meeting.agenda_items.create!(title: "Dredging permit", order_index: 1)
    item.agenda_item_topics.create!(topic: topic)
  end

  test "anonymous visitor sees the heading but not the activity" do
    set_access_mode("gated")

    get committee_path(@committee.slug)

    assert_response :success
    assert_match(/What They&#39;ve Been Working On|What They've Been Working On/, response.body)
    assert_no_match(/#{Regexp.escape(WITHHELD)}/i, response.body)
    assert_match(/Sign in to keep reading/, response.body)
  end

  test "signed-in member sees the activity" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "committee-reader@example.com", status: "active"))

    get committee_path(@committee.slug)

    assert_match(/#{Regexp.escape(WITHHELD)}/i, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
