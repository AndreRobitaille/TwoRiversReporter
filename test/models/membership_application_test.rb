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
      city: "Two Rivers",
      state: "WI"
    )

    assert_predicate application, :valid?
  end

  test "status must be one of the allowed values" do
    user = User.create!(email_address: "applicant@example.com", status: "pending")

    application = MembershipApplication.new(user: user, status: "draft")

    assert_not application.valid?
    assert_includes application.errors[:status], "is not included in the list"
  end
end
