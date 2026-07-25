require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  test "admin approves submitted application and sends approval link" do
    admin = create_passkey_admin
    applicant = User.create!(email_address: "approve@example.com", status: "pending")
    application = applicant.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
    sign_in(admin)
    delivered = false

    TransactionalEmail.stub(:application_approved, ->(_user, _application, _magic_link) {
      Object.new.tap do |message|
        message.define_singleton_method(:deliver_now) do
          delivered = true
        end
      end
    }) do
      assert_difference("MagicLink.where(purpose: 'sign_in').count", 1) do
        with_admin_access { patch approve_user_path(applicant) }
      end
    end

    assert_redirected_to user_path(applicant)
    assert_predicate delivered, :itself
    assert_equal "active", applicant.reload.status
    assert_predicate applicant.disabled_at, :blank?
    assert_equal "approved", application.reload.status
  end

  test "admin approval remains retryable when approval email construction fails" do
    admin = create_passkey_admin
    applicant = User.create!(email_address: "approve-fail@example.com", status: "pending")
    application = applicant.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
    sign_in(admin)

    TransactionalEmail.stub(:application_approved, ->(_user, _application, _magic_link) {
      raise TransactionalEmail::MissingTransactionalId, "missing id"
    }) do
      assert_raises(TransactionalEmail::MissingTransactionalId) do
        with_admin_access { patch approve_user_path(applicant) }
      end
    end

    assert_equal "pending", applicant.reload.status
    assert_equal "submitted", application.reload.status
    assert_equal 0, MagicLink.where(user: applicant, purpose: "sign_in").count
  end

  test "admin approval re-raises stale review errors without compensation" do
    admin = create_passkey_admin
    applicant = User.create!(email_address: "stale@example.com", status: "pending")
    applicant.membership_applications.create!(status: "approved", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
    session = admin.sessions.create!(ip_address: "127.0.0.1", user_agent: "test", last_seen_at: Time.current)
    Current.session = session

    controller = Admin::UsersController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.response = ActionDispatch::TestResponse.new
    controller.instance_variable_set(:@user, applicant)

    assert_raises(ActiveRecord::RecordNotFound) { controller.send(:approve) }

    assert_equal "pending", applicant.reload.status
    assert_equal 0, MagicLink.where(user: applicant, purpose: "sign_in").count
  ensure
    Current.session = nil
  end

  test "admin approval remains retryable when approval email delivery raises non delivery errors" do
    admin = create_passkey_admin
    applicant = User.create!(email_address: "approve-runtime@example.com", status: "pending")
    application = applicant.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
    sign_in(admin)

    TransactionalEmail.stub(:application_approved, ->(_user, _application, _magic_link) {
      Object.new.tap do |message|
        message.define_singleton_method(:deliver_now) { raise RuntimeError, "delivery failed" }
      end
    }) do
      assert_raises(RuntimeError) do
        with_admin_access { patch approve_user_path(applicant) }
      end
    end

    assert_equal "pending", applicant.reload.status
    assert_equal "submitted", application.reload.status
    assert_equal 0, MagicLink.where(user: applicant, purpose: "sign_in").count
  end

  test "admin rejects submitted application" do
    admin = create_passkey_admin
    applicant = User.create!(email_address: "reject@example.com", status: "pending")
    application = applicant.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
    sign_in(admin)

    with_admin_access { patch reject_user_path(applicant), params: { rejection_reason: "Not verified" } }

    assert_redirected_to user_path(applicant)
    assert_equal "rejected", applicant.reload.status
    assert_equal "rejected", application.reload.status
    assert_equal "Not verified", application.rejection_reason
  end

  test "admin can toggle admin role disable user and revoke sessions" do
    admin = create_passkey_admin
    user = User.create!(email_address: "managed@example.com", status: "active")
    session = user.sessions.create!(ip_address: "127.0.0.1", user_agent: "test", last_seen_at: Time.current)
    sign_in(admin)

    with_admin_access { patch toggle_admin_user_path(user) }
    assert user.reload.admin?

    with_admin_access { patch disable_user_path(user) }
    assert user.reload.disabled_at.present?

    with_admin_access { delete revoke_session_user_path(user, session_id: session.id) }
    assert_not Session.exists?(session.id)
  end

  test "admin can re-enable a disabled user but not a pending applicant" do
    admin = create_passkey_admin
    user = User.create!(email_address: "reenable@example.com", status: "active", disabled_at: Time.current)
    applicant = User.create!(email_address: "pending@example.com", status: "pending", disabled_at: Time.current)
    sign_in(admin)

    with_admin_access { patch disable_user_path(user) }

    assert_nil user.reload.disabled_at
    assert_redirected_to user_path(user)

    with_admin_access { patch disable_user_path(applicant) }

    assert_predicate applicant.reload.disabled_at, :present?
    assert_redirected_to user_path(applicant)
  end

  test "admin can revoke all sessions for a user" do
    admin = create_passkey_admin
    user = User.create!(email_address: "managed-all@example.com", status: "active")
    first_session = user.sessions.create!(ip_address: "127.0.0.1", user_agent: "test", last_seen_at: Time.current)
    user.sessions.create!(ip_address: "127.0.0.1", user_agent: "test", last_seen_at: 1.minute.ago)
    sign_in(admin)

    with_admin_access { delete revoke_all_sessions_user_path(user) }

    assert_not Session.exists?(first_session.id)
    assert_equal 0, user.sessions.count
  end

  test "admin can create a passwordless admin user" do
    admin = create_passkey_admin
    sign_in(admin)

    assert_difference("User.where(email_address: 'newadmin@example.com').count", 1) do
      with_admin_access do
        post users_path, params: { user: { email_address: "newadmin@example.com" } }
      end
    end

    created = User.find_by!(email_address: "newadmin@example.com")
    assert created.admin?
    assert_equal "active", created.status
    assert_redirected_to user_path(created)
    assert_equal "Admin user created.", flash[:notice]
  end

  test "admin user create requires an email address" do
    admin = create_passkey_admin
    sign_in(admin)

    with_admin_access do
      post users_path, params: { user: { email_address: "" } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Email address can&#39;t be blank"
  end

  test "new admin user form is passwordless and does not mention MFA" do
    admin = create_passkey_admin
    sign_in(admin)

    with_admin_access { get new_user_path }

    assert_response :success
    assert_includes response.body, "Create an active admin account."
    assert_includes response.body, "<input"
    assert_includes response.body, "name=\"user[email_address]\""
    assert_includes response.body, "autocomplete=\"username\""
    assert_includes response.body, "Create admin"
    assert_no_match(/password/i, response.body)
    assert_no_match(/mfa/i, response.body)
    assert_no_match(/temporary password/i, response.body)
    assert_no_match(/totp/i, response.body)
  end

  # Applications submitted before street became required have none on file.
  # Approving one saves the record, so a blanket presence validation would make
  # them permanently unreviewable.
  test "admin can still approve an application submitted before street was required" do
    admin = create_passkey_admin
    applicant = User.create!(email_address: "legacy-approve@example.com", status: "pending")
    application = applicant.membership_applications.create!(
      status: "submitted",
      first_name: "Legacy",
      last_name: "Applicant",
      street: "123 Main St",
      city: "Two Rivers",
      state: "WI"
    )
    application.update_column(:street, nil)
    sign_in(admin)

    TransactionalEmail.stub(:application_approved, ->(_user, _application, _magic_link) {
      Object.new.tap { |message| message.define_singleton_method(:deliver_now) { true } }
    }) do
      with_admin_access { patch approve_user_path(applicant) }
    end

    assert_redirected_to user_path(applicant)
    assert_equal "approved", application.reload.status
    assert_equal "active", applicant.reload.status
  end

  test "admin can still reject an application submitted before street was required" do
    admin = create_passkey_admin
    applicant = User.create!(email_address: "legacy-reject@example.com", status: "pending")
    application = applicant.membership_applications.create!(
      status: "submitted",
      first_name: "Legacy",
      last_name: "Applicant",
      street: "123 Main St",
      city: "Two Rivers",
      state: "WI"
    )
    application.update_column(:street, nil)
    sign_in(admin)

    with_admin_access { patch reject_user_path(applicant), params: { rejection_reason: "Not a resident." } }

    assert_redirected_to user_path(applicant)
    assert_equal "rejected", application.reload.status
    assert_equal "Not a resident.", application.rejection_reason
  end

  test "index and show reflect account and application management details" do
    admin = create_passkey_admin
    user = User.create!(email_address: "ui@example.com", status: "active")
    disabled_user = User.create!(email_address: "ui-disabled@example.com", status: "active", disabled_at: Time.current)
    user.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "public-key", sign_count: 0)
    user.sessions.create!(ip_address: "127.0.0.1", user_agent: "test agent", last_seen_at: Time.current, created_at: 1.day.ago)
    user.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI", facebook_profile_url: "https://facebook.com/jane", application_notes: "Hello", created_at: 2.days.ago)
    sign_in(admin)

    with_admin_access do
      get users_path
      assert_response :success
      assert_includes response.body, "Account management"
      assert_includes response.body, "Status"
      assert_includes response.body, "Passkeys"
      assert_includes response.body, "Application"
      assert_includes response.body, "Submitted"

      get user_path(user)
      assert_response :success
      assert_includes response.body, "Account and application management"
      assert_includes response.body, "Membership applications"
      assert_includes response.body, "Created"
      assert_includes response.body, "Hello"
      assert_includes response.body, "123 Main St"
      assert_includes response.body, "Facebook profile"
      assert_includes response.body, "1 passkey"
      assert_includes response.body, "Session history"
      assert_includes response.body, "127.0.0.1"
      assert_includes response.body, "test agent"
      assert_includes response.body, "Signed in"
      assert_includes response.body, "Last seen"
      assert_includes response.body, "Status"
      assert_includes response.body, "Rejection reason"
      assert_includes response.body, "Disable account"

      get user_path(disabled_user)
      assert_response :success
      assert_includes response.body, "Re-enable account"
    end
  end

  private

    def create_passkey_admin
      user = User.create!(email_address: "admin@example.com", admin: true, status: "active")
      user.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "public-key", sign_count: 0)
      user
    end

    def sign_in(user)
      sign_in_as_admin(user)
    end

    def with_admin_access
      yield
    end
end
