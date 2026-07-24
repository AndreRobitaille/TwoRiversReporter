require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "new users receive a webauthn id" do
    user = User.create!(email_address: "Member@Example.COM", password: "password123", password_confirmation: "password123")

    assert user.webauthn_id.present?
    assert_equal "member@example.com", user.email_address
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

  test "passkey prompt suppression expires after timestamp" do
    user = User.create!(email_address: "prompt@example.com", password: "password123", password_confirmation: "password123", status: "active", passkey_prompt_dismissed_until: 1.day.from_now)

    assert user.passkey_prompt_dismissed?

    user.update!(passkey_prompt_dismissed_until: 1.minute.ago)

    assert_not user.passkey_prompt_dismissed?
  end
end
