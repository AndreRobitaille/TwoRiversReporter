require "test_helper"

class MagicLinkTest < ActiveSupport::TestCase
  test "create_for persists digest and keeps raw token in memory only" do
    user = User.create!(email_address: "active@example.com", status: "active")

    magic_link = MagicLink.create_for!(user, purpose: "admin_login")

    assert_predicate magic_link, :persisted?
    assert_predicate magic_link.raw_token, :present?
    assert_not_equal magic_link.raw_token, magic_link.token_digest
    assert_equal MagicLink.send(:digest_token, magic_link.raw_token), magic_link.token_digest
  end

  test "consume! succeeds once and marks token used" do
    user = User.create!(email_address: "active@example.com", status: "active")
    magic_link = MagicLink.create_for!(user, purpose: "admin_login")

    consumed = MagicLink.consume!(magic_link.raw_token, purpose: "admin_login")

    assert_equal magic_link.id, consumed.id
    assert_predicate consumed.used_at, :present?
    assert_raises(MagicLink::InvalidToken) { MagicLink.consume!(magic_link.raw_token, purpose: "admin_login") }
  end

  test "consume! rejects expired inactive wrong purpose and missing token" do
    active_user = User.create!(email_address: "active@example.com", status: "active")
    inactive_user = User.create!(email_address: "inactive@example.com", status: "pending")

    expired = MagicLink.create_for!(active_user, purpose: "admin_login", expires_at: 1.minute.ago)
    inactive = MagicLink.create_for!(inactive_user, purpose: "admin_login")
    wrong_purpose = MagicLink.create_for!(active_user, purpose: "password_reset")

    assert_raises(MagicLink::InvalidToken) { MagicLink.consume!(expired.raw_token, purpose: "admin_login") }
    assert_raises(MagicLink::InvalidToken) { MagicLink.consume!(inactive.raw_token, purpose: "admin_login") }
    assert_raises(MagicLink::InvalidToken) { MagicLink.consume!(wrong_purpose.raw_token, purpose: "admin_login") }
    assert_raises(MagicLink::InvalidToken) { MagicLink.consume!("missing-token", purpose: "admin_login") }
  end
end
