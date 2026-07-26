require "test_helper"

class MembershipApplicationTest < ActiveSupport::TestCase
  test "email_pending applications can omit the submitted fields" do
    user = User.create!(email_address: "applicant@example.com", status: "pending")

    application = MembershipApplication.new(user: user, status: "email_pending")

    assert_predicate application, :valid?
  end

  test "submitted applications require identity and location fields" do
    user = User.create!(email_address: "applicant@example.com", status: "pending")

    application = MembershipApplication.new(user: user, status: "submitted")

    assert_not application.valid?
    assert_includes application.errors[:first_name], "can't be blank"
    assert_includes application.errors[:last_name], "can't be blank"
    assert_includes application.errors[:street], "can't be blank"
    assert_includes application.errors[:city], "can't be blank"
    assert_includes application.errors[:state], "can't be blank"
  end

  test "submitted applications are valid once the required fields are present" do
    user = User.create!(email_address: "applicant@example.com", status: "pending")

    application = MembershipApplication.new(
      user: user,
      status: "submitted",
      first_name: "Jane",
      last_name: "Member",
      street: "123 Main St",
      city: "Two Rivers",
      state: "WI"
    )

    assert_predicate application, :valid?
  end

  test "an application being submitted without a street is invalid" do
    user = User.create!(email_address: "applicant@example.com", status: "pending")
    application = user.membership_applications.create!(status: "email_pending")

    assert_not application.update(
      status: "submitted",
      first_name: "Jane",
      last_name: "Member",
      city: "Two Rivers",
      state: "WI"
    )
    assert_includes application.errors[:street], "can't be blank"
    assert_equal "email_pending", application.reload.status
  end

  # The grandfather clause in MembershipApplication#street_required?. Rows that
  # were submitted before street became required must stay saveable, or the
  # admin can never approve or reject them.
  test "an application already submitted without a street can still be reviewed" do
    user = User.create!(email_address: "legacy@example.com", status: "pending")
    application = user.membership_applications.create!(
      status: "submitted",
      first_name: "Legacy",
      last_name: "Applicant",
      street: "123 Main St",
      city: "Two Rivers",
      state: "WI"
    )
    application.update_column(:street, nil)
    application.reload

    assert application.update(status: "approved", reviewed_at: Time.current),
      "a legacy blank-street application must still be approvable: #{application.errors.full_messages.inspect}"
    assert_equal "approved", application.reload.status
  end

  test "editing a legacy application's street back to blank is still rejected" do
    user = User.create!(email_address: "legacy-edit@example.com", status: "pending")
    application = user.membership_applications.create!(
      status: "submitted",
      first_name: "Legacy",
      last_name: "Applicant",
      street: "123 Main St",
      city: "Two Rivers",
      state: "WI"
    )

    assert_not application.update(street: "")
    assert_includes application.errors[:street], "can't be blank"
  end

  test "phone is optional and round-trips" do
    user = User.create!(email_address: "phone@example.com", status: "pending")

    without_phone = user.membership_applications.create!(
      status: "submitted",
      first_name: "Jane",
      last_name: "Member",
      street: "123 Main St",
      city: "Two Rivers",
      state: "WI"
    )
    assert_nil without_phone.reload.phone

    without_phone.update!(phone: "(920) 555-0148 ext. 2")
    assert_equal "(920) 555-0148 ext. 2", without_phone.reload.phone
  end

  test "Facebook profile URLs must use HTTPS and a Facebook host" do
    application = build_submitted_application

    [
      "javascript:alert(document.domain)",
      "http://facebook.com/jane",
      "https://facebook.com.evil.example/jane",
      "https://example.com/jane"
    ].each do |unsafe_url|
      application.facebook_profile_url = unsafe_url

      assert_not application.valid?, "#{unsafe_url.inspect} should be rejected"
      assert_includes application.errors[:facebook_profile_url], "must be a secure Facebook URL"
    end

    [ "https://facebook.com/jane", "https://www.facebook.com/jane", "https://m.facebook.com/jane" ].each do |safe_url|
      application.facebook_profile_url = safe_url

      assert application.valid?, "#{safe_url.inspect} should be accepted"
    end
  end

  test "a legacy unsafe Facebook URL does not prevent reviewing an application" do
    application = build_submitted_application
    application.save!
    application.update_column(:facebook_profile_url, "javascript:alert(document.domain)")

    assert application.update(status: "approved", reviewed_at: Time.current)
  end

  test "status must be one of the allowed values" do
    user = User.create!(email_address: "applicant@example.com", status: "pending")

    application = MembershipApplication.new(user: user, status: "draft")

    assert_not application.valid?
    assert_includes application.errors[:status], "is not included in the list"
  end

  private

    def build_submitted_application
      user = User.create!(email_address: "facebook-profile-#{SecureRandom.hex(4)}@example.com", status: "pending")
      MembershipApplication.new(
        user: user,
        status: "submitted",
        first_name: "Jane",
        last_name: "Member",
        street: "123 Main St",
        city: "Two Rivers",
        state: "WI"
      )
    end
end
