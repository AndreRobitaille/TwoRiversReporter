require "test_helper"

class SiteAccessTest < ActionDispatch::IntegrationTest
  test "anonymous visitor is gated when the mode is gated" do
    set_access_mode("gated")

    get root_path

    assert_response :success
    assert @controller.send(:gated_for_visitor?)
  end

  test "anonymous visitor is not gated when the mode is open" do
    set_access_mode("open")

    get root_path

    assert_not @controller.send(:gated_for_visitor?)
  end

  test "authenticated member is never gated" do
    set_access_mode("gated")
    user = User.create!(email_address: "member@example.com", status: "active")
    sign_in_as(user)

    get root_path

    assert_not @controller.send(:gated_for_visitor?)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
