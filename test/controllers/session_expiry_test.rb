require "test_helper"

class SessionExpiryTest < ActionDispatch::IntegrationTest
  test "a session past the absolute lifetime is cleared on the next request" do
    user = User.create!(email_address: "aged@example.com", status: "active")
    session = sign_in_as(user)
    session.update_columns(created_at: 400.days.ago, last_seen_at: Time.current)

    get settings_security_url

    assert_redirected_to new_public_session_url
    assert_not Session.exists?(session.id), "the expired session row is destroyed, not merely ignored"
  end

  test "a session idle past the inactivity limit is cleared on the next request" do
    user = User.create!(email_address: "idle@example.com", status: "active")
    session = sign_in_as(user)
    session.update_columns(last_seen_at: 61.days.ago)

    get settings_security_url

    assert_redirected_to new_public_session_url
    assert_not Session.exists?(session.id)
  end

  test "a live session is not cleared" do
    user = User.create!(email_address: "live@example.com", status: "active")
    session = sign_in_as(user)

    get settings_security_url

    assert_response :success
    assert Session.exists?(session.id)
  end
end
