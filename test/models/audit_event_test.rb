require "test_helper"

class AuditEventTest < ActiveSupport::TestCase
  setup do
    @admin = User.create!(email_address: "auditor@example.com", admin: true, status: "active")
    @second_admin = User.create!(email_address: "auditor2@example.com", admin: true, status: "active")
    @second_admin.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "public-key", sign_count: 0)
  end

  test "record! snapshots the actor email and the subject label" do
    subject = User.create!(email_address: "subject@example.com", status: "active")

    event = AuditEvent.record!(actor: @admin, action: "user.destroy", subject: subject, label: subject.email_address)

    assert_equal @admin.id, event.actor_id
    assert_equal "auditor@example.com", event.actor_email
    assert_equal "user.destroy", event.action
    assert_equal "subject@example.com", event.subject_label
  end

  test "the record survives deletion of its subject" do
    subject = User.create!(email_address: "doomed@example.com", status: "active")
    event = AuditEvent.record!(actor: @admin, action: "user.destroy", subject: subject, label: subject.email_address)

    subject.destroy!

    event.reload
    assert_equal "doomed@example.com", event.subject_label,
      "an audit trail that loses the identity of what it recorded is not a trail"
  end

  # Without has_many :audit_events, dependent: :nullify on User, this raises
  # ActiveRecord::InvalidForeignKey — and it raises only for accounts that have
  # done admin work, so it passes against a freshly created user and fails in
  # production against the owner.
  test "deleting an actor does not break user deletion" do
    AuditEvent.record!(actor: @admin, action: "user.destroy", label: "someone@example.com")

    assert_nothing_raised { @admin.destroy! }
  end

  test "deleting an actor preserves the recorded email" do
    event = AuditEvent.record!(actor: @admin, action: "user.destroy", label: "someone@example.com")

    @admin.destroy!

    event.reload
    assert_nil event.actor_id
    assert_equal "auditor@example.com", event.actor_email
  end

  test "record! captures the request ip when given a request" do
    request = ActionDispatch::TestRequest.create("REMOTE_ADDR" => "203.0.113.45")

    event = AuditEvent.record!(actor: @admin, action: "site_setting.update", request: request)

    assert_equal "203.0.113.45", event.ip_address
  end
end
