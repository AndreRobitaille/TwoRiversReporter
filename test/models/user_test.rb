require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "new users receive a webauthn id" do
    user = User.create!(email_address: "Member@Example.COM")

    assert user.webauthn_id.present?
    assert_equal "member@example.com", user.email_address
  end

  test "admins without explicit status default active and non-admins default pending" do
    admin = User.create!(email_address: "admin-default@example.com", admin: true)
    member = User.create!(email_address: "member-default@example.com")

    assert_equal "active", admin.status
    assert admin.active_for_authentication?
    assert_equal "pending", member.status
    assert_not member.active_for_authentication?
  end

  test "explicit admin status is preserved on later updates" do
    admin = User.create!(email_address: "admin-pending@example.com", admin: true, status: "pending")

    assert_equal "pending", admin.status

    admin.update!(disabled_at: Time.current)

    assert_equal "pending", admin.reload.status
  end

  test "nil status backfills active for admins and pending for non-admins" do
    admin = User.connection.select_one(<<~SQL.squish)
      INSERT INTO users (email_address, admin, status, webauthn_id, created_at, updated_at)
      VALUES ('admin-nil-status@example.com', true, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING *
    SQL
    member = User.connection.select_one(<<~SQL.squish)
      INSERT INTO users (email_address, admin, status, webauthn_id, created_at, updated_at)
      VALUES ('member-nil-status@example.com', false, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING *
    SQL

    admin_user = User.find(admin["id"])
    member_user = User.find(member["id"])

    admin_user.update!(disabled_at: Time.current)
    member_user.update!(disabled_at: Time.current)

    assert_equal "active", admin_user.reload.status
    assert_equal "pending", member_user.reload.status
  end

  test "active users can authenticate but pending rejected and disabled users cannot" do
    active = User.create!(email_address: "active@example.com", status: "active")
    pending = User.create!(email_address: "pending@example.com", status: "pending")
    rejected = User.create!(email_address: "rejected@example.com", status: "rejected")
    disabled = User.create!(email_address: "disabled@example.com", status: "active", disabled_at: Time.current)

    assert active.active_for_authentication?
    assert_not pending.active_for_authentication?
    assert_not rejected.active_for_authentication?
    assert_not disabled.active_for_authentication?
  end

  test "admin access requires admin status, active authentication, and at least one passkey" do
    non_admin_with_passkey = User.create!(email_address: "member-with-passkey@example.com", status: "active")
    admin_with_passkey = User.create!(email_address: "admin-with-passkey@example.com", status: "active", admin: true)
    PasskeyCredential.create!(external_id: "cred-123", public_key: "public-key", sign_count: 0, user: non_admin_with_passkey)
    PasskeyCredential.create!(external_id: "cred-456", public_key: "public-key", sign_count: 0, user: admin_with_passkey)
    inactive_admin = User.create!(email_address: "inactive-admin@example.com", status: "pending", admin: true)
    PasskeyCredential.create!(external_id: "cred-789", public_key: "public-key", sign_count: 0, user: inactive_admin)

    assert_not non_admin_with_passkey.admin_access_ready?
    assert admin_with_passkey.admin_access_ready?
    assert_not inactive_admin.admin_access_ready?
  end

  test "legacy users with null passwordless fields are backfilled on update" do
    user = User.connection.select_one(<<~SQL.squish)
      INSERT INTO users (email_address, admin, status, webauthn_id, created_at, updated_at)
      VALUES ('legacy@example.com', false, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING *
    SQL

    legacy = User.find(user["id"])

    assert_nil legacy.read_attribute_before_type_cast("status")
    assert_nil legacy.webauthn_id

    legacy.update!(admin: true)

    assert_equal "active", legacy.status
    assert legacy.webauthn_id.present?
  end

  test "status rejects disabled and nil" do
    user = User.new(email_address: "status@example.com")

    user.status = "disabled"
    assert_not user.valid?
    assert_not_empty user.errors[:status]

    user.status = nil
    assert user.valid?
    assert_equal "pending", user.status
  end

  test "an address with no @ is rejected server side" do
    user = User.new(email_address: "asdf")

    assert_not user.valid?
    assert_includes user.errors[:email_address], "is not a valid email address"
  end

  test "structurally broken addresses are rejected" do
    [ "asdf", "no-at-sign.example.com", "@example.com", "spaces in@example.com", "trailing@", "two@@example.com" ].each do |bad|
      user = User.new(email_address: bad)

      assert_not user.valid?, "#{bad.inspect} should be rejected"
      assert_not_empty user.errors[:email_address], "#{bad.inspect} should carry a format error"
    end
  end

  test "an invalid address cannot be persisted" do
    assert_raises(ActiveRecord::RecordInvalid) { User.create!(email_address: "asdf") }
    assert_not User.exists?(email_address: "asdf")
  end

  test "legitimate but unusual addresses are accepted" do
    [ "first.last+tag@sub.example.co.uk", "x@example.com", "o'brien@example.com", "user_name@example-host.com" ].each do |good|
      user = User.new(email_address: good)

      assert user.valid?, "#{good.inspect} should be accepted, got #{user.errors[:email_address].inspect}"
    end
  end

  test "blank addresses report presence only, not a second format complaint" do
    user = User.new(email_address: "")

    assert_not user.valid?
    assert_equal [ "can't be blank" ], user.errors[:email_address]
  end

  test "a pre-existing row with a bad address stays saveable so an admin can still act on it" do
    legacy = User.connection.select_one(<<~SQL.squish)
      INSERT INTO users (email_address, admin, status, webauthn_id, created_at, updated_at)
      VALUES ('junk-address-legacy', false, 'pending', 'wa-legacy-junk', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING *
    SQL

    user = User.find(legacy["id"])

    assert_nothing_raised { user.update!(status: "rejected") }
    assert_equal "rejected", user.reload.status
  end

  test "changing a pre-existing bad address to another bad one is still rejected" do
    legacy = User.connection.select_one(<<~SQL.squish)
      INSERT INTO users (email_address, admin, status, webauthn_id, created_at, updated_at)
      VALUES ('junk-address-legacy-2', false, 'pending', 'wa-legacy-junk-2', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING *
    SQL

    user = User.find(legacy["id"])
    user.email_address = "still-junk"

    assert_not user.valid?
    assert_not_empty user.errors[:email_address]
  end

  test "deliverable_address? mirrors the model validation without touching the database" do
    assert User.deliverable_address?("member@example.com")
    assert_not User.deliverable_address?("asdf")
    assert_not User.deliverable_address?(nil)
    assert_not User.deliverable_address?("")
  end

  test "last_admin? is true only for a sole admin" do
    sole = User.create!(email_address: "sole-admin@example.com", admin: true)
    member = User.create!(email_address: "sole-member@example.com")

    assert_predicate sole, :last_admin?
    assert_not_predicate member, :last_admin?

    second = User.create!(email_address: "second-admin@example.com", admin: true)

    assert_not_predicate sole.reload, :last_admin?
    assert_not_predicate second, :last_admin?
  end

  test "destroying the last admin is refused even outside the admin controller" do
    sole = User.create!(email_address: "irreplaceable@example.com", admin: true, status: "active")

    assert_raises(User::LastAdminError) { sole.destroy! }
    assert User.exists?(sole.id), "the site's only admin must survive a destroy attempt"
  end

  test "the last admin guard blocks destroy even with non-admin members present" do
    sole = User.create!(email_address: "irreplaceable-2@example.com", admin: true, status: "active")
    User.create!(email_address: "just-a-member@example.com", status: "active")

    assert_raises(User::LastAdminError) { sole.destroy! }
    assert User.exists?(sole.id), "ordinary members are not a substitute for an admin"
  end

  test "a refused deletion leaves the admin's passkeys and sessions intact" do
    sole = User.create!(email_address: "irreplaceable-3@example.com", admin: true, status: "active")
    passkey = sole.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "public-key", sign_count: 0)
    session = sole.sessions.create!(user_agent: "test", ip_address: "127.0.0.1", last_seen_at: Time.current)

    assert_raises(User::LastAdminError) { sole.destroy! }

    assert PasskeyCredential.exists?(passkey.id), "a refused deletion must not strip the admin's passkey"
    assert Session.exists?(session.id), "a refused deletion must not sign the admin out"
  end

  test "an admin can be destroyed once another admin exists" do
    first = User.create!(email_address: "handover-from@example.com", admin: true, status: "active")
    User.create!(email_address: "handover-to@example.com", admin: true, status: "active")

    assert_nothing_raised { first.destroy! }
    assert_not User.exists?(first.id)
  end

  test "deleting a user takes its own records and leaves referencing rows standing" do
    admin = User.create!(email_address: "departing-admin@example.com", admin: true, status: "active")
    other_admin = User.create!(email_address: "remaining-admin@example.com", admin: true, status: "active")

    admin.sessions.create!(user_agent: "test", ip_address: "127.0.0.1", last_seen_at: Time.current)
    admin.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "public-key", sign_count: 0)
    MagicLink.create_for!(admin, purpose: "sign_in")
    own_application = admin.membership_applications.create!(status: "email_pending")

    # Owned by somebody else, merely pointing at the admin who is leaving.
    applicant = User.create!(email_address: "reviewed-by-departing@example.com", status: "active")
    reviewed = applicant.membership_applications.create!(
      status: "approved", first_name: "Jane", last_name: "Member", street: "1 Main St",
      city: "Two Rivers", state: "WI", reviewed_by: admin, reviewed_at: Time.current
    )
    topic = Topic.create!(name: "user-deletion-audit-trail")
    review_event = TopicReviewEvent.create!(topic: topic, user: admin, action: "approved")

    admin_id = admin.id
    admin.destroy!

    assert_not User.exists?(admin_id)
    assert_empty Session.where(user_id: admin_id)
    assert_empty PasskeyCredential.where(user_id: admin_id)
    assert_empty MagicLink.where(user_id: admin_id)
    assert_not MembershipApplication.exists?(own_application.id)

    assert MembershipApplication.exists?(reviewed.id), "another person's application must outlive its reviewer"
    assert_nil reviewed.reload.reviewed_by_id
    assert TopicReviewEvent.exists?(review_event.id), "the moderation audit trail must outlive the moderator"
    assert_nil review_event.reload.user_id
    assert_empty MembershipApplication.where(reviewed_by_id: admin_id)
    assert_empty TopicReviewEvent.where(user_id: admin_id)
    assert_predicate other_admin.reload, :persisted?
  end

  test "deleting a user nullifies generated images they uploaded rather than destroying site content" do
    admin = User.create!(email_address: "image-uploader@example.com", admin: true, status: "active")
    User.create!(email_address: "image-uploader-backup@example.com", admin: true, status: "active")
    topic = Topic.create!(name: "user-deletion-uploaded-image")
    image = GeneratedImage.create!(imageable: topic, status: "ready", uploaded_by: admin, admin_override: true)

    admin_id = admin.id
    admin.destroy!

    assert GeneratedImage.exists?(image.id), "an uploaded image is site content and must survive its uploader"
    assert_nil image.reload.uploaded_by_id
    assert_empty GeneratedImage.where(uploaded_by_id: admin_id)
  end

  test "passkey prompt suppression expires after timestamp" do
    user = User.create!(email_address: "prompt@example.com", status: "active", passkey_prompt_dismissed_until: 1.day.from_now)

    assert user.passkey_prompt_dismissed?

    user.update!(passkey_prompt_dismissed_until: 1.minute.ago)

    assert_not user.passkey_prompt_dismissed?
  end
end
