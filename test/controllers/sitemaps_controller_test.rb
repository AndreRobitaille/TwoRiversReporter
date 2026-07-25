require "test_helper"

class SitemapsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @approved_topic = Topic.create!(name: "downtown tif district", status: "approved", lifecycle_status: "active")
    @blocked_topic = Topic.create!(name: "infrastructure", status: "blocked", lifecycle_status: "active")
    @meeting = Meeting.create!(body_name: "City Council", starts_at: 1.day.ago, detail_page_url: "https://example.com/meetings/1")
    @member = Member.create!(name: "Public Member")
    @committee = Committee.create!(name: "City Council")
  end

  test "renders xml with correct content type" do
    get sitemap_path
    assert_response :success
    assert_equal "application/xml; charset=utf-8", @response.content_type
  end

  test "includes only public static pages" do
    get sitemap_path
    assert_includes @response.body, root_url
    assert_includes @response.body, about_url
    assert_not_includes @response.body, meetings_url
    assert_not_includes @response.body, topics_url
    assert_not_includes @response.body, committees_url
  end

  test "includes no protected resource URLs" do
    get sitemap_path
    assert_includes @response.body, root_url
    assert_includes @response.body, about_url
    assert_not_includes @response.body, meetings_url
    assert_not_includes @response.body, topics_url
    assert_not_includes @response.body, committees_url
    assert_not_includes @response.body, meeting_url(@meeting)
    assert_not_includes @response.body, topic_url(@approved_topic)
    assert_not_includes @response.body, topic_url(@blocked_topic)
    assert_not_includes @response.body, member_url(@member)
    assert_not_includes @response.body, committee_url(@committee.slug)
  end
end
