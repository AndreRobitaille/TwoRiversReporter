require "test_helper"

class Admin::ApiKeyVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "key-admin@example.test", admin: true, status: "active")
    @owner = User.create!(email_address: "provisioned@example.test", status: "active")
    @active, @plaintext = ApiAccessToken.issue!(user: @owner, name: "<script>Purpose canary</script>", expires_in: 90.days)
    @expired, = ApiAccessToken.issue!(user: @owner, name: "Expired notebook", expires_in: 30.days)
    @expired.update!(expires_at: 1.minute.ago)
    @revoked, = ApiAccessToken.issue!(user: @owner, name: "Revoked notebook", expires_in: 30.days)
    @revoked.revoke!(actor: @owner)
    sign_in_as(@admin)
  end

  test "account list shows provisioned history separately from usable keys" do
    get users_path
    assert_response :success
    assert_select "tr", text: /provisioned@example.test.*3 provisioned · 1 active/m
    assert_select "th", text: "API keys", count: 1
    @owner.update!(disabled_at: Time.current)
    get users_path
    assert_select "tr", text: /provisioned@example.test.*3 provisioned · 0 active/m
  end

  test "detail lists purpose names and states while never rendering secret material" do
    get user_path(@owner)
    assert_response :success
    assert_select ".api-key-name", text: @active.name
    assert_select ".api-key-entry script", count: 0
    %w[Active Expired Revoked].each { |state| assert_select ".api-key-entry .badge", text: state }
    assert_not_includes response.body, @plaintext
    [ @active, @expired, @revoked ].each { |key| assert_not_includes response.body, key.secret_digest }
    @owner.update!(disabled_at: Time.current)
    get user_path(@owner)
    assert_select ".api-key-entry .badge", text: "Suspended — account disabled"
    get user_path(@admin)
    assert_includes response.body, "No API keys have been provisioned for this account."
  end

  test "ordinary owners cannot read administrator key metadata" do
    sign_in_as(@owner)
    get user_path(@owner)
    assert_response :redirect
    assert_not_includes response.body, @active.name
  end
end
