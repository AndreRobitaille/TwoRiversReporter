require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "new users receive a webauthn id" do
    user = User.create!(email_address: "Member@Example.COM", password: "password123", password_confirmation: "password123")

    assert user.webauthn_id.present?
    assert_equal "member@example.com", user.email_address
  end

  test "admins without explicit status default active and non-admins default pending" do
    admin = User.create!(email_address: "admin-default@example.com", password: "password123", password_confirmation: "password123", admin: true)
    member = User.create!(email_address: "member-default@example.com", password: "password123", password_confirmation: "password123")

    assert_equal "active", admin.status
    assert admin.active_for_authentication?
    assert_equal "pending", member.status
    assert_not member.active_for_authentication?
  end

  test "active users can authenticate but pending rejected and disabled users cannot" do
    active = User.create!(email_address: "active@example.com", password: "password123", password_confirmation: "password123", status: "active")
    pending = User.create!(email_address: "pending@example.com", password: "password123", password_confirmation: "password123", status: "pending")
    rejected = User.create!(email_address: "rejected@example.com", password: "password123", password_confirmation: "password123", status: "rejected")
    disabled = User.create!(email_address: "disabled@example.com", password: "password123", password_confirmation: "password123", status: "active", disabled_at: Time.current)

    assert active.active_for_authentication?
    assert_not pending.active_for_authentication?
    assert_not rejected.active_for_authentication?
    assert_not disabled.active_for_authentication?
  end

  test "admin access requires admin status, active authentication, and at least one passkey" do
    non_admin_with_passkey = User.create!(email_address: "member-with-passkey@example.com", password: "password123", password_confirmation: "password123", status: "active")
    admin_with_passkey = User.create!(email_address: "admin-with-passkey@example.com", password: "password123", password_confirmation: "password123", status: "active", admin: true)
    PasskeyCredential.create!(external_id: "cred-123", public_key: "public-key", sign_count: 0, user: non_admin_with_passkey)
    PasskeyCredential.create!(external_id: "cred-456", public_key: "public-key", sign_count: 0, user: admin_with_passkey)
    inactive_admin = User.create!(email_address: "inactive-admin@example.com", password: "password123", password_confirmation: "password123", status: "pending", admin: true)
    PasskeyCredential.create!(external_id: "cred-789", public_key: "public-key", sign_count: 0, user: inactive_admin)

    assert_not non_admin_with_passkey.admin_access_ready?
    assert admin_with_passkey.admin_access_ready?
    assert_not inactive_admin.admin_access_ready?
  end

  test "legacy users with null passwordless fields are backfilled on update" do
    user = User.connection.select_one(<<~SQL.squish)
      INSERT INTO users (email_address, password_digest, admin, status, webauthn_id, created_at, updated_at)
      VALUES ('legacy@example.com', '#{BCrypt::Password.create("password123")}', false, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING *
    SQL

    legacy = User.find(user["id"])

    assert_nil legacy.read_attribute_before_type_cast("status")
    assert_nil legacy.webauthn_id

    legacy.update!(admin: true)

    assert_equal "active", legacy.status
    assert legacy.webauthn_id.present?
  end

  test "status rejects disabled and nil" do
    user = User.new(email_address: "status@example.com", password: "password123", password_confirmation: "password123")

    user.status = "disabled"
    assert_not user.valid?
    assert_not_empty user.errors[:status]

    user.status = nil
    assert user.valid?
    assert_equal "pending", user.status
  end

  test "passkey prompt suppression expires after timestamp" do
    user = User.create!(email_address: "prompt@example.com", password: "password123", password_confirmation: "password123", status: "active", passkey_prompt_dismissed_until: 1.day.from_now)

    assert user.passkey_prompt_dismissed?

    user.update!(passkey_prompt_dismissed_until: 1.minute.ago)

    assert_not user.passkey_prompt_dismissed?
  end
end
