require "test_helper"

class SessionEligibilityJourneysTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "eligibility-member@example.com", status: "active")
    link = MagicLink.create_for!(@user, purpose: "sign_in")
    post magic_link_public_session_path, params: { token: link.raw_token }
    get settings_profile_path

    assert_response :success
    assert_select ".detail-value", text: @user.email_address
    @session = @user.sessions.sole
    @formerly_valid_cookie = cookies[:session_id]
  end

  test "revoked session loses own-account access on the next request and on cookie replay" do
    @session.destroy!
    assert_next_request_and_replay_denied
  end

  test "idle expired session loses own-account access on the next request and on cookie replay" do
    @session.update_columns(last_seen_at: 61.days.ago)
    assert_next_request_and_replay_denied
  end

  test "absolutely expired session loses own-account access on the next request and on cookie replay" do
    @session.update_columns(created_at: 400.days.ago)
    assert_next_request_and_replay_denied
  end

  test "disabled account loses own-account access on the next request and on cookie replay" do
    @user.update!(disabled_at: Time.current)
    assert_next_request_and_replay_denied
  end

  test "pending account loses own-account access on the next request and on cookie replay" do
    @user.update!(status: "pending", disabled_at: Time.current)
    assert_next_request_and_replay_denied
  end

  test "rejected account loses own-account access on the next request and on cookie replay" do
    @user.update!(status: "rejected", disabled_at: Time.current)
    assert_next_request_and_replay_denied
  end

  private

    def assert_next_request_and_replay_denied
      get settings_profile_path
      assert_redirected_to new_public_session_path
      assert_not Session.exists?(@session.id)
      assert_predicate cookies[:session_id], :blank?

      cookies[:session_id] = @formerly_valid_cookie
      get settings_profile_path
      assert_redirected_to new_public_session_path
      assert_predicate cookies[:session_id], :blank?
      assert_empty @user.sessions.reload
    end
end
