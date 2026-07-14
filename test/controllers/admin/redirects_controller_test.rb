require "test_helper"

class Admin::RedirectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "redirect-admin@test.com", password: "password", admin: true, totp_enabled: true)
    @admin.ensure_totp_secret!

    post session_url, params: { email_address: "redirect-admin@test.com", password: "password" }
    follow_redirect!

    totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
    post mfa_session_url, params: { code: totp.now }
    follow_redirect!

    @redirect = Redirect.create!(source_path: "/topics/766", destination: "/topics/176")
  end

  test "requires admin authentication" do
    reset!
    get admin_redirects_url
    assert_redirected_to new_session_url
  end

  test "index lists redirects" do
    get admin_redirects_url
    assert_response :success
    assert_select "td", text: "/topics/766"
  end

  test "new renders form" do
    get new_admin_redirect_url
    assert_response :success
  end

  test "create saves a valid redirect and normalizes the source path" do
    assert_difference "Redirect.count", 1 do
      post admin_redirects_url, params: { redirect: { source_path: "meetings/9?ref=x", destination: "/meetings/10" } }
    end
    assert_equal "/meetings/9", Redirect.last.source_path
  end

  test "create rejects an invalid redirect" do
    assert_no_difference "Redirect.count" do
      post admin_redirects_url, params: { redirect: { source_path: "/loop", destination: "/loop" } }
    end
    assert_response :unprocessable_entity
  end

  test "update changes the destination" do
    patch admin_redirect_url(@redirect), params: { redirect: { destination: "/topics/200" } }
    assert_equal "/topics/200", @redirect.reload.destination
  end

  test "destroy removes the redirect" do
    assert_difference "Redirect.count", -1 do
      delete admin_redirect_url(@redirect)
    end
  end
end
