require "test_helper"

class RedirectMiddlewareTest < ActionDispatch::IntegrationTest
  test "301s a request whose path has a redirect" do
    Redirect.create!(source_path: "/topics/766", destination: "/topics/176")

    get "/topics/766"

    assert_response :moved_permanently
    assert_equal "/topics/176", response.headers["Location"]
  end

  test "honors a custom status code" do
    Redirect.create!(source_path: "/old", destination: "/new", status_code: 302)

    get "/old"

    assert_response :found
    assert_equal "/new", response.headers["Location"]
  end

  test "matches regardless of a trailing slash or query string" do
    Redirect.create!(source_path: "/topics/766", destination: "/topics/176")

    get "/topics/766/?ref=home"

    assert_response :moved_permanently
    assert_equal "/topics/176", response.headers["Location"]
  end

  test "passes through paths with no redirect" do
    get "/topics"
    assert_response :success
  end

  test "increments the hit counter" do
    r = Redirect.create!(source_path: "/old", destination: "/new")

    get "/old"

    assert_equal 1, r.reload.hits
  end

  test "does not redirect non-GET requests" do
    Redirect.create!(source_path: "/old", destination: "/new")

    post "/old"

    assert_not_equal "/new", response.headers["Location"]
  end
end
