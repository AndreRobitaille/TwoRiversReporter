require "test_helper"

class TopicsExploreControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "member@example.com", status: "active")
    sign_in_as(@user)
  end

  test "explore page renders with back link to topics" do
    get topics_explore_url
    assert_response :success
    assert_select "a[href=?]", topics_path
  end
end
