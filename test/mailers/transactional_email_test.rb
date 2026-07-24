require "test_helper"

class TransactionalEmailTest < ActionMailer::TestCase
  test "magic_link includes the raw token in the delivered body" do
    user = User.create!(email_address: "active@example.com", password: "password123", password_confirmation: "password123", status: "active")
    magic_link = MagicLink.create_for!(user, purpose: "sign_in")

    mail = TransactionalEmail.magic_link(user.email_address, magic_link.raw_token)

    assert_includes mail.body.decoded, magic_link.raw_token
  end
end
