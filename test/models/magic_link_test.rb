require "test_helper"

class MagicLinkTest < ActiveSupport::TestCase
  test "create_for persists digest and keeps raw token in memory only" do
    user = User.create!(email_address: "active@example.com", status: "active")

    magic_link = MagicLink.create_for!(user, purpose: "sign_in")

    assert_predicate magic_link, :persisted?
    assert_predicate magic_link.raw_token, :present?
    assert_not_equal magic_link.raw_token, magic_link.token_digest
    assert_equal MagicLink.send(:digest_token, magic_link.raw_token), magic_link.token_digest
  end

  test "consume! succeeds once and marks token used for sign in" do
    user = User.create!(email_address: "active@example.com", status: "active")
    magic_link = MagicLink.create_for!(user, purpose: "sign_in")

    consumed = MagicLink.consume!(magic_link.raw_token, purpose: "sign_in")

    assert_equal magic_link.id, consumed.id
    assert_predicate consumed.used_at, :present?
    assert_raises(MagicLink::InvalidToken) { MagicLink.consume!(magic_link.raw_token, purpose: "sign_in") }
  end

  test "consume! enforces active sign in and pending application rules" do
    active_user = User.create!(email_address: "active@example.com", status: "active")
    inactive_user = User.create!(email_address: "inactive@example.com", status: "pending")
    pending_disabled_user = User.create!(email_address: "pending-disabled@example.com", status: "pending", disabled_at: Time.current)

    expired = MagicLink.create_for!(active_user, purpose: "sign_in", expires_at: 1.minute.ago)
    inactive = MagicLink.create_for!(inactive_user, purpose: "sign_in")
    application_link = MagicLink.create_for!(pending_disabled_user, purpose: "application")

    assert_raises(MagicLink::InvalidToken) { MagicLink.consume!(expired.raw_token, purpose: "sign_in") }
    assert_raises(MagicLink::InvalidToken) { MagicLink.consume!(inactive.raw_token, purpose: "sign_in") }
    assert_equal application_link.id, MagicLink.consume!(application_link.raw_token, purpose: "application").id
    assert_raises(MagicLink::InvalidToken) { MagicLink.consume!("missing-token", purpose: "sign_in") }
  end
end
