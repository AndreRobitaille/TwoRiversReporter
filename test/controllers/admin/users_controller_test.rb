require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  test "admin approves submitted application and sends approval link" do
    admin = create_passkey_admin
    applicant = User.create!(email_address: "approve@example.com", password: "password", status: "pending")
    application = applicant.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", city: "Two Rivers", state: "WI")
    sign_in(admin)

    assert_difference("MagicLink.count", 1) do
      with_admin_access { patch approve_user_path(applicant) }
    end

    assert_redirected_to user_path(applicant)
    assert_equal "active", applicant.reload.status
    assert_equal "approved", application.reload.status
  end

  test "admin rejects submitted application" do
    admin = create_passkey_admin
    applicant = User.create!(email_address: "reject@example.com", password: "password", status: "pending")
    application = applicant.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", city: "Two Rivers", state: "WI")
    sign_in(admin)

    with_admin_access { patch reject_user_path(applicant), params: { rejection_reason: "Not verified" } }

    assert_redirected_to user_path(applicant)
    assert_equal "rejected", applicant.reload.status
    assert_equal "rejected", application.reload.status
    assert_equal "Not verified", application.rejection_reason
  end

  test "admin can toggle admin role disable user and revoke sessions" do
    admin = create_passkey_admin
    user = User.create!(email_address: "managed@example.com", password: "password", status: "active")
    session = user.sessions.create!(ip_address: "127.0.0.1", user_agent: "test", last_seen_at: Time.current)
    sign_in(admin)

    with_admin_access { patch toggle_admin_user_path(user) }
    assert user.reload.admin?

    with_admin_access { patch disable_user_path(user) }
    assert user.reload.disabled_at.present?

    with_admin_access { delete revoke_session_user_path(user, session_id: session.id) }
    assert_not Session.exists?(session.id)
  end

  private

    def create_passkey_admin
      user = User.create!(email_address: "admin@example.com", password: "password", admin: true, status: "active")
      user.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "public-key", sign_count: 0)
      user
    end

    def sign_in(user)
      AdminMfaPolicy.stub(:enforced?, false) do
        post session_url, params: { email_address: user.email_address, password: "password" }
      end
    end

    def with_admin_access(&block)
      AdminMfaPolicy.stub(:enforced?, false, &block)
    end
end
