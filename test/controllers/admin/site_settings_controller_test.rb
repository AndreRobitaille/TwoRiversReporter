require "test_helper"

class Admin::SiteSettingsControllerTest < ActionDispatch::IntegrationTest
  test "admin can switch the site to gated" do
    sign_in_as_admin(create_passkey_admin)
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "open", singleton_guard: 0)

    patch admin_site_settings_path, params: { site_setting: { access_mode: "gated" } }

    assert_redirected_to admin_site_settings_path
    assert_equal "gated", SiteSetting.access_mode
  end

  test "an unknown mode is rejected and the current mode survives" do
    sign_in_as_admin(create_passkey_admin)
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "open", singleton_guard: 0)

    patch admin_site_settings_path, params: { site_setting: { access_mode: "sideways" } }

    assert_response :unprocessable_entity
    assert_equal "open", SiteSetting.access_mode
  end

  test "a rejected mode re-renders with the persisted mode still selected" do
    sign_in_as_admin(create_passkey_admin)
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "open", singleton_guard: 0)

    patch admin_site_settings_path, params: { site_setting: { access_mode: "sideways" } }

    assert_response :unprocessable_entity
    assert_includes response.body, "Access mode is not included in the list"
    assert_match(/type="radio"[^>]*value="open"[^>]*checked="checked"/, response.body)
    assert_no_match(/type="radio"[^>]*value="gated"[^>]*checked="checked"/, response.body)
  end

  test "non-admins cannot reach the toggle" do
    get admin_site_settings_path

    assert_response :redirect
  end

  private

    def create_passkey_admin
      user = User.create!(email_address: "settings-admin@example.com", admin: true, status: "active")
      user.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "public-key", sign_count: 0)
      user
    end
end
