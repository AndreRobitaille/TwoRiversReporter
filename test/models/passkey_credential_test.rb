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

  test "records ownership metadata" do
    user = User.create!(email_address: "owner@example.com", password: "password123", password_confirmation: "password123")

    credential = PasskeyCredential.create!(
      user: user,
      external_id: "credential-123",
      public_key: "public-key",
      sign_count: 0,
      nickname: "Work laptop"
    )

    assert_equal user, credential.user
    assert_equal "credential-123", credential.external_id
    assert_equal "Work laptop", credential.nickname
  end
end
