require "test_helper"

module Settings
  class ProfileControllerTest < ActionDispatch::IntegrationTest
    test "requires authentication" do
      get settings_profile_path

      assert_redirected_to new_public_session_path
    end

    test "shows the current account and latest membership application" do
      user = User.create!(email_address: "profile@example.com", status: "active")
      reviewer = User.create!(email_address: "reviewer@example.com", status: "active")

      user.membership_applications.create!(status: "email_pending", created_at: 3.days.ago)
      latest_application = user.membership_applications.create!(
        status: "submitted",
        first_name: "Jane",
        last_name: "Member",
        street: "123 Main St",
        city: "Two Rivers",
        state: "WI",
        facebook_profile_url: "https://facebook.com/jane.member",
        application_notes: "Please review my application.",
        submitted_at: 2.days.ago,
        reviewed_at: 1.day.ago,
        reviewed_by: reviewer,
        created_at: 1.day.ago
      )

      sign_in_as(user)
      get settings_profile_path

      assert_response :success
      assert_select "h1", text: "Account"
      assert_select "nav.tab-bar a[aria-current='page']", text: "Profile"
      assert_includes response.body, user.email_address
      assert_includes response.body, "Active"
      assert_includes response.body, "Membership application"
      assert_includes response.body, latest_application.first_name
      assert_includes response.body, latest_application.street
      assert_includes response.body, latest_application.facebook_profile_url
      assert_includes response.body, latest_application.application_notes
      assert_not_includes response.body, reviewer.email_address
      assert_includes response.body, "Submitted"
    end

    # A member granted access directly (the owner's own admin account is the
    # motivating case) has no application row. Inviting them to apply for
    # access they already hold is nonsense, and reads as an account error.
    test "active member with no application is not invited to apply" do
      user = User.create!(email_address: "granted@example.com", status: "active")

      sign_in_as(user)
      get settings_profile_path

      assert_response :success
      assert_includes response.body, "Membership application"
      assert_not_includes response.body, "Start an application"
      assert_includes response.body, "Your account is active"
    end

    # The invitation must survive for people who genuinely need it. Only an
    # active user can hold a session (Authentication#resume_session drops the
    # cookie otherwise), so the pending case is unreachable from here and is
    # covered at the view level instead — see
    # test/views/settings_profile_show_test.rb.
  end
end
