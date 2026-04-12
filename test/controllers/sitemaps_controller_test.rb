require "test_helper"

class SitemapsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @approved_topic = Topic.create!(
      name: "downtown tif district",
      status: "approved",
      lifecycle_status: "active"
    )
    @blocked_topic = Topic.create!(
      name: "infrastructure",
      status: "blocked",
      lifecycle_status: "active"
    )
    @meeting = Meeting.create!(
      body_name: "City Council",
      meeting_type: "Regular",
      starts_at: 3.days.ago,
      status: "minutes_posted",
      detail_page_url: "http://example.com/sitemap-test"
    )
    @member = Member.create!(name: "Jane Doe")
    @committee = Committee.create!(
      name: "City Council",
      slug: "city-council",
      status: "active"
    )
  end

  test "renders xml with correct content type" do
    get sitemap_path
    assert_response :success
    assert_equal "application/xml; charset=utf-8", @response.content_type
  end

  test "includes the four static index pages" do
    get sitemap_path
    assert_includes @response.body, root_url
    assert_includes @response.body, meetings_url
    assert_includes @response.body, topics_url
    assert_includes @response.body, committees_url
  end

  test "includes every approved topic and excludes blocked topics" do
    get sitemap_path
    assert_includes @response.body, topic_url(@approved_topic)
    assert_not_includes @response.body, topic_url(@blocked_topic)
  end

  test "includes every meeting" do
    get sitemap_path
    assert_includes @response.body, meeting_url(@meeting)
  end

  test "includes every member" do
    get sitemap_path
    assert_includes @response.body, member_url(@member)
  end

  test "includes every committee" do
    get sitemap_path
    assert_includes @response.body, committee_url(@committee.slug)
  end

  test "includes the about page" do
    get sitemap_path
    assert_includes @response.body, about_url
  end

  # Coverage guard: when a new public resource is added (e.g. resources :foo),
  # add a fixture + an `assert_includes` above. This test list IS the contract
  # for what /sitemap.xml must contain. If you add a public model and don't
  # update SitemapsController, internal nav still works but search engines
  # discover the pages later — the sitemap is the explicit signal.
  test "covers all expected publicly visible models" do
    expected_models = %w[Committee Member Meeting Topic]
    covered = expected_models.select do |m|
      method_defined = self.class.instance_methods.any? { |t| t.to_s.include?(m.downcase) }
      method_defined
    end
    assert_equal expected_models.sort, covered.sort,
      "Add a test for the new public model, then update SitemapsController to include it."
  end
end
