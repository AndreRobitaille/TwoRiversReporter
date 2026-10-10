require "test_helper"

class ApiAccessTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "api-owner@example.test", status: "active")
  end

  test "named credentials store only a digest and retain one-time lifecycle audit snapshots" do
    token, plaintext = issue(name: "  Research notebook  ")
    assert_equal "Research notebook", token.name
    assert_match(/\Atrr_[0-9a-f]{24}_[0-9a-f]{64}\z/, plaintext)
    assert_equal token.id, ApiAccessToken.authenticate(plaintext).id
    assert_not_includes token.attributes.values, plaintext
    assert_not_includes token.attributes.values, plaintext.split("_").last
    event = AuditEvent.find_by!(action: "api_key.create", subject: token)
    assert_equal token.name, event.subject_label
    assert_not_includes event.to_json, plaintext
    assert_not_includes event.to_json, token.secret_digest
    token.revoke!(actor: @user)
    assert_nil ApiAccessToken.authenticate(plaintext)
    assert_no_difference "AuditEvent.count" do
      token.revoke!(actor: @user)
    end
    @user.destroy!
    assert_not ApiAccessToken.exists?(token.id)
    assert_nil event.reload.actor
    assert_equal "api-owner@example.test", event.actor_email
    assert_equal "Research notebook", event.subject_label
  end

  test "malformed wrong expired revoked and inactive-owner keys all fail" do
    token, plaintext = issue
    assert_nil ApiAccessToken.authenticate("invalid")
    assert_nil ApiAccessToken.authenticate(plaintext.sub(/.$/, plaintext.end_with?("0") ? "1" : "0"))
    travel_to token.expires_at, with_usec: true do
      assert_nil ApiAccessToken.authenticate(plaintext)
    end
    %w[pending rejected].each do |status|
      @user.update!(status: status)
      assert_nil ApiAccessToken.authenticate(plaintext)
    end
    @user.update!(status: "active", disabled_at: Time.current)
    assert_nil ApiAccessToken.authenticate(plaintext)
    assert_equal :suspended, token.reload.state
    @user.update!(disabled_at: nil)
    assert_equal token.id, ApiAccessToken.authenticate(plaintext).id
    token.revoke!(actor: @user)
    assert_equal :revoked, token.reload.state
    assert_nil ApiAccessToken.authenticate(plaintext)
  end

  test "purpose names are trimmed required and bounded but not unique" do
    [ " ", "x" * 81 ].each do |name|
      assert_raises(ActiveRecord::RecordInvalid) { issue(name: name) }
    end
    issue(name: "Notebook")
    assert_difference "ApiAccessToken.count", 1 do
      issue(name: "Notebook")
    end
  end

  test "last-use metadata writes are throttled without changing token lifecycle" do
    token, plaintext = issue
    token.update!(last_used_at: 5.minutes.ago)
    assert_no_changes -> { token.reload.last_used_at } do
      ApiAccessToken.authenticate(plaintext)
    end
    token.update!(last_used_at: 16.minutes.ago)
    assert_changes -> { token.reload.last_used_at } do
      ApiAccessToken.authenticate(plaintext)
    end
  end

  private

    def issue(name: "Notebook")
      ApiAccessToken.issue!(user: @user, name: name, expires_in: 90.days)
    end
end
