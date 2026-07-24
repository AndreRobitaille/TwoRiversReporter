require "test_helper"

module Settings
  class ProfileControllerTest < ActionDispatch::IntegrationTest
    test "requires authentication" do
      get settings_profile_path

      assert_redirected_to new_public_session_path
    end

    test "shows the current account and latest membership application" do
      user = User.create!(email_address: "profile@example.com", password: "password123", password_confirmation: "password123", status: "active")
      reviewer = User.create!(email_address: "reviewer@example.com", password: "password123", password_confirmation: "password123", status: "active")

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

      get settings_profile_path, headers: signed_session_headers(user)

      assert_response :success
      assert_select "h1", text: "Profile"
      assert_includes response.body, user.email_address
      assert_includes response.body, "Active"
      assert_includes response.body, "Latest membership application"
      assert_includes response.body, latest_application.first_name
      assert_includes response.body, latest_application.street
      assert_includes response.body, latest_application.facebook_profile_url
      assert_includes response.body, latest_application.application_notes
      assert_not_includes response.body, reviewer.email_address
      assert_includes response.body, "Submitted"
    end

    private

      def signed_session_headers(user)
        session = Session.create!(user: user, last_seen_at: Time.current)
        req = ActionDispatch::TestRequest.create
        jar = ActionDispatch::Cookies::CookieJar.build(req, {})
        jar.signed[:session_id] = session.id
        { "Cookie" => jar.to_header }
      end
  end
end
