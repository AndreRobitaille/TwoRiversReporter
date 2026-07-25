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

  test "status must be one of the allowed values" do
    user = User.create!(email_address: "applicant@example.com", status: "pending")

    application = MembershipApplication.new(user: user, status: "draft")

    assert_not application.valid?
    assert_includes application.errors[:status], "is not included in the list"
  end
end
