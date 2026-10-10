require "test_helper"

class Settings::ApiKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "key-settings@example.test", status: "active")
  end

  test "owner creates a named key once then sees only metadata and can revoke it" do
    sign_in_as(@user)
    get new_settings_api_key_path
    assert_response :success
    assert_select "input[name='api_access_token[name]'][required][maxlength='80']"
    post settings_api_keys_path, params: { api_access_token: { name: "Home dashboard", expires_in_days: "90" } }
    assert_response :created
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    plaintext = css_select("#api-key-secret").sole.text
    key = ApiAccessToken.authenticate(plaintext)
    assert_equal "Home dashboard", key.name
    assert_select "h2", text: "Home dashboard"
    get settings_api_keys_path
    assert_response :success
    assert_select "h3", text: "Home dashboard"
    assert_not_includes response.body, plaintext
    assert_not_includes response.body, key.secret_digest
    delete settings_api_key_path(key)
    assert_redirected_to settings_api_keys_path
    assert_nil ApiAccessToken.authenticate(plaintext)
  end

  test "issuance requires both freshness and matching context while revocation remains available" do
    session = sign_in_as(@user)
    key, = ApiAccessToken.issue!(user: @user, name: "Existing", expires_in: 30.days)
    session.update!(reauthenticated_at: 16.minutes.ago)
    get new_settings_api_key_path
    assert_redirected_to new_reauthentication_path
    assert_no_difference "ApiAccessToken.count" do
      post settings_api_keys_path, params: { api_access_token: { name: "Blocked", expires_in_days: "90" } }
    end
    assert_redirected_to new_reauthentication_path
    session.update!(reauthenticated_at: Time.current, ip_prefix: "192.0.2.0/24")
    assert_no_difference "ApiAccessToken.count" do
      post settings_api_keys_path, params: { api_access_token: { name: "Blocked", expires_in_days: "90" } }
    end
    assert_redirected_to new_reauthentication_path
    delete settings_api_key_path(key)
    assert_redirected_to settings_api_keys_path
    assert_equal :revoked, key.reload.state
  end

  test "invalid form preserves purpose and reports errors without issuing a key" do
    sign_in_as(@user)
    [ { name: " ", expires_in_days: "90" }, { name: "My notebook", expires_in_days: "999" } ].each do |values|
      assert_no_difference "ApiAccessToken.count" do
        post settings_api_keys_path, params: { api_access_token: values }
      end
      assert_response :unprocessable_entity
      assert_select "[role='alert']"
    end
    assert_select "input[name='api_access_token[name]'][value='My notebook']"
  end

  test "owners cannot list or revoke other owners keys and revoke-all is scoped" do
    other = User.create!(email_address: "other-keys@example.test", status: "active")
    theirs, their_secret = ApiAccessToken.issue!(user: other, name: "Other purpose canary", expires_in: 90.days)
    mine, = ApiAccessToken.issue!(user: @user, name: "Mine", expires_in: 90.days)
    sign_in_as(@user)
    get settings_api_keys_path
    assert_includes response.body, "Mine"
    assert_not_includes response.body, theirs.name
    delete settings_api_key_path(theirs)
    assert_not theirs.reload.revoked_at?
    delete revoke_all_settings_api_keys_path
    assert_equal :revoked, mine.reload.state
    assert ApiAccessToken.authenticate(their_secret)
  end

  test "browser issuance and revocation retain CSRF protection" do
    sign_in_as(@user)
    previous = Settings::ApiKeysController.allow_forgery_protection
    Settings::ApiKeysController.allow_forgery_protection = true
    get new_settings_api_key_path
    csrf = css_select("input[name='authenticity_token']").sole["value"]
    assert_no_difference "ApiAccessToken.count" do
      post settings_api_keys_path, params: { api_access_token: { name: "CSRF check", expires_in_days: "30" } }
    end
    assert_response :unprocessable_entity
    assert_difference "ApiAccessToken.count", 1 do
      post settings_api_keys_path, params: { authenticity_token: csrf,
        api_access_token: { name: "CSRF check", expires_in_days: "30" } }
    end
    assert_response :created
    key = @user.api_access_tokens.newest_first.first
    delete settings_api_key_path(key)
    assert_response :unprocessable_entity
    assert_not key.reload.revoked_at?
  ensure
    Settings::ApiKeysController.allow_forgery_protection = previous
  end

  test "bearer credentials cannot provision revoke or view keys or authenticate admin" do
    @user.update!(admin: true)
    key, plaintext = ApiAccessToken.issue!(user: @user, name: "Admin resident tool", expires_in: 30.days)
    headers = { "Authorization" => "Bearer #{plaintext}" }
    [ settings_api_keys_path, new_settings_api_key_path, users_path, user_path(@user) ].each do |path|
      get path, headers: headers
      assert_response :redirect
    end
    assert_no_difference "ApiAccessToken.count" do
      post settings_api_keys_path, params: { api_access_token: { name: "No", expires_in_days: "90" } }, headers: headers
    end
    delete settings_api_key_path(key), headers: headers
    assert_not key.reload.revoked_at?
  end
end
