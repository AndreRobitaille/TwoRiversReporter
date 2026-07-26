require "test_helper"

module Admin
  class AuditEventsTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "recorder@example.com", admin: true, status: "active")
      @second_admin = User.create!(email_address: "recorder2@example.com", admin: true, status: "active")
      @member = User.create!(email_address: "recorded@example.com", status: "active")
    end

    test "deleting a user records an audit event that outlives them" do
      sign_in_as(@admin)

      assert_difference -> { AuditEvent.where(action: "user.destroy").count }, 1 do
        delete user_url(@member)
      end

      event = AuditEvent.where(action: "user.destroy").last
      assert_equal "recorded@example.com", event.subject_label
      assert_equal "recorder@example.com", event.actor_email
    end

    test "a refused last-admin deletion leaves no audit row" do
      sign_in_as(@admin)
      # Bring the world down to a single admin so the model-level guard fires;
      # bypass the controller's own self-deletion guard the same way
      # Admin::UsersControllerTest does, so it's the model's LastAdminError we
      # are exercising, not the earlier controller-level refusal.
      @second_admin.destroy!

      without_self_deletion_guard do
        assert_no_difference -> { AuditEvent.where(action: "user.destroy").count } do
          delete user_url(@admin)
        end
      end

      assert_redirected_to user_path(@admin)
      assert_equal "At least one active admin with a passkey must remain.", flash[:alert]
    end

    test "deleting an application records an audit event" do
      application = @member.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
      sign_in_as(@admin)

      assert_difference -> { AuditEvent.where(action: "membership_application.destroy").count }, 1 do
        delete admin_membership_application_url(application)
      end
    end

    test "changing the access mode records an audit event with both values" do
      sign_in_as(@admin)
      SiteSetting.instance.update!(access_mode: "open")

      # The brief's original draft used `post` here, but the singular
      # `resource :site_settings, only: %i[show update]` route only answers
      # to PATCH/PUT (confirmed via `bin/rails routes`); `post` 404s before
      # the action, and the "controller" method is untouched by an unrouted request.
      patch admin_site_settings_url, params: { site_setting: { access_mode: "gated" } }

      event = AuditEvent.where(action: "site_setting.access_mode").last
      assert_equal "open", event.metadata["from"]
      assert_equal "gated", event.metadata["to"]
    end

    test "granting admin records an audit event" do
      sign_in_as(@admin)

      assert_difference -> { AuditEvent.where(action: "user.toggle_admin").count }, 1 do
        patch toggle_admin_user_url(@member)
      end
    end

    test "creating an admin user records an audit event" do
      sign_in_as(@admin)

      assert_difference -> { AuditEvent.where(action: "user.create").count }, 1 do
        post users_url, params: { user: { email_address: "newadmin@example.com" } }
      end

      event = AuditEvent.where(action: "user.create").last
      assert_equal "newadmin@example.com", event.subject_label
      assert_equal "recorder@example.com", event.actor_email
    end

    test "approving an application records an audit event" do
      @member.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
      sign_in_as(@admin)

      TransactionalEmail.stub(:application_approved, ->(_user, _application, _magic_link) {
        Object.new.tap { |message| message.define_singleton_method(:deliver_now) { true } }
      }) do
        assert_difference -> { AuditEvent.where(action: "membership_application.approve").count }, 1 do
          patch approve_user_url(@member)
        end
      end

      event = AuditEvent.where(action: "membership_application.approve").last
      assert_equal "recorded@example.com", event.subject_label
    end

    test "rejecting an application records an audit event" do
      @member.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
      sign_in_as(@admin)

      assert_difference -> { AuditEvent.where(action: "membership_application.reject").count }, 1 do
        patch reject_user_url(@member), params: { rejection_reason: "Not verified" }
      end

      event = AuditEvent.where(action: "membership_application.reject").last
      assert_equal "recorded@example.com", event.subject_label
      assert_equal "Not verified", event.metadata["reason"]
    end

    test "disabling a user records an audit event" do
      sign_in_as(@admin)

      assert_difference -> { AuditEvent.where(action: "user.disable").count }, 1 do
        patch disable_user_url(@member)
      end

      event = AuditEvent.where(action: "user.disable").last
      assert_equal "recorded@example.com", event.subject_label
      assert_equal true, event.metadata["disabled"]
    end

    test "re-enabling a disabled active user records an audit event with disabled false" do
      # A distinct call site from the disable branch above: @user.disabled_at
      # present AND status active is the only path into the re-enable branch
      # (lines 91-95), which is otherwise untested — a user that is only
      # disabled (not pending) hits this branch, not the "remains disabled" one.
      disabled_user = User.create!(email_address: "disabled-audit@example.com", status: "active", disabled_at: Time.current)
      sign_in_as(@admin)

      assert_difference -> { AuditEvent.where(action: "user.disable").count }, 1 do
        patch disable_user_url(disabled_user)
      end

      event = AuditEvent.where(action: "user.disable").last
      assert_equal "disabled-audit@example.com", event.subject_label
      assert_equal false, event.metadata["disabled"]
    end

    test "disabling a pending, already-disabled applicant is a no-op and records nothing" do
      # The "remains disabled" branch is a no-op on a pending applicant; it
      # must not record an event for a state change that never happened.
      applicant = User.create!(email_address: "pending-audit@example.com", status: "pending", disabled_at: Time.current)
      sign_in_as(@admin)

      assert_no_difference -> { AuditEvent.where(action: "user.disable").count } do
        patch disable_user_url(applicant)
      end
    end

    test "revoking a session records an audit event" do
      session = @member.sessions.create!(ip_address: "127.0.0.1", user_agent: "test", last_seen_at: Time.current)
      sign_in_as(@admin)

      assert_difference -> { AuditEvent.where(action: "session.revoke").count }, 1 do
        delete revoke_session_user_url(@member, session_id: session.id)
      end

      event = AuditEvent.where(action: "session.revoke").last
      assert_equal "recorded@example.com", event.subject_label
    end

    test "revoking all sessions records an audit event" do
      @member.sessions.create!(ip_address: "127.0.0.1", user_agent: "test", last_seen_at: Time.current)
      @member.sessions.create!(ip_address: "127.0.0.1", user_agent: "test", last_seen_at: 1.minute.ago)
      sign_in_as(@admin)

      assert_difference -> { AuditEvent.where(action: "session.revoke_all").count }, 1 do
        delete revoke_all_sessions_user_url(@member)
      end

      event = AuditEvent.where(action: "session.revoke_all").last
      assert_equal "recorded@example.com", event.subject_label
      assert_equal 2, event.metadata["count"]
    end

    test "the index lists recorded events" do
      AuditEvent.record!(actor: @admin, action: "user.destroy", label: "gone@example.com")
      sign_in_as(@admin)

      get admin_audit_events_url

      assert_response :success
      assert_select "body", text: /gone@example\.com/
    end

    test "the index is admin only" do
      sign_in_as(@member)

      get admin_audit_events_url

      assert_redirected_to root_url
    end

    private

      # Minitest parallelises by forking, and tests inside a process run
      # serially, so swapping a method on the controller class is contained
      # to this example. Mirrors Admin::UsersControllerTest.
      def without_self_deletion_guard
        klass = Admin::UsersController
        original = klass.instance_method(:refuse_self_deletion)
        klass.send(:define_method, :refuse_self_deletion) { nil }
        klass.send(:private, :refuse_self_deletion)
        yield
      ensure
        klass.send(:define_method, :refuse_self_deletion, original)
        klass.send(:private, :refuse_self_deletion)
      end
  end
end
