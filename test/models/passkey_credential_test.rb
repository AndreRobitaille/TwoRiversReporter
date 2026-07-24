require "test_helper"

class PasskeyCredentialTest < ActiveSupport::TestCase
  test "belongs to a user and validates required fields" do
    user = User.create!(email_address: "passkey@example.com", password: "password123", password_confirmation: "password123")

    credential = PasskeyCredential.new(user: user, sign_count: nil)

    assert_not credential.valid?
    assert_not_empty credential.errors[:external_id]
    assert_not_empty credential.errors[:public_key]
    assert_not_empty credential.errors[:sign_count]
  end
end
