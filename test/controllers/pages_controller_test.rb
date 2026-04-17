require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "about page renders successfully" do
    get about_path
    assert_response :success
  end

  test "about page has correct title" do
    get about_path
    assert_select "title", /Plain English/
  end

  test "about page contains anchor links" do
    get about_path
    assert_select "a[href='#how-it-works']"
    assert_select "a[href='#your-questions']"
    assert_select "a[href='#why-this-exists']"
    assert_select "a[href='#under-the-hood']"
  end

  test "about page contains all four zones" do
    get about_path
    assert_select "#how-it-works"
    assert_select "#your-questions"
    assert_select "#why-this-exists"
    assert_select "#under-the-hood"
  end
end
