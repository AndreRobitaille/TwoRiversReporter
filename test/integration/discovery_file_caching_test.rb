require "test_helper"

class DiscoveryFileCachingTest < ActionDispatch::IntegrationTest
  test "public discovery files use an hour of freshness with revalidation for GET HEAD and conditional requests" do
    [ "/robots.txt", "/llms.txt" ].each do |path|
      get path
      assert_response :success
      assert_equal "public, max-age=3600, must-revalidate", response.headers["Cache-Control"]
      modified = response.headers.fetch("Last-Modified")

      head path
      assert_response :success
      assert_empty response.body
      assert_equal "public, max-age=3600, must-revalidate", response.headers["Cache-Control"]

      get path, headers: { "If-Modified-Since" => modified }
      assert_response :not_modified
      assert_equal "public, max-age=3600, must-revalidate", response.headers["Cache-Control"]
    end
  end

  test "other response caches remain intact" do
    [ [ "/assets/application-fingerprint.css", "public, max-age=31536000" ],
      [ "/sitemap.xml", "private, no-store" ],
      [ "/topics/1", "private, no-store" ] ].each do |path, cache_control|
      body = [ "example response" ]
      middleware = DiscoveryFileCaching.new(->(_env) { [ 200, { "cache-control" => cache_control }, body ] })
      status, headers, actual_body = middleware.call(Rack::MockRequest.env_for(path))
      assert_equal 200, status
      assert_equal cache_control, headers["cache-control"]
      assert_same body, actual_body
    end
  end
end
