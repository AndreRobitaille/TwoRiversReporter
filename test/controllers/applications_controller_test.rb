require "test_helper"

class ApplicationsControllerTest < ActionDispatch::IntegrationTest
  test "application start creates a pending disabled user and non enumerating response" do
    assert_difference("User.count", 1) do
      assert_difference("MembershipApplication.count", 1) do
        assert_no_enqueued_jobs do
          post applications_path, params: { email_address: "Applicant@Example.com" }
        end
      end
    end

    user = User.find_by!(email_address: "applicant@example.com")
    assert_equal "pending", user.status
    assert_not user.active_for_authentication?
    assert_predicate user.disabled_at, :present?
    assert_redirected_to new_application_path
    assert_equal "Check your email for the application link.", flash[:notice]
  end

  test "verified application form renders from the application token" do
    user = User.create!(email_address: "verified@example.com", password: "password123", password_confirmation: "password123", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    get edit_application_path(application, token: link.raw_token)

    assert_response :success
    assert_includes response.body, "Facebook profile"
    assert_select "form[action='#{application_path(application)}'][method='post']"
  end

  test "application submission records details and queues admin notification" do
    user = User.create!(email_address: "submit@example.com", password: "password123", password_confirmation: "password123", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    assert_enqueued_with(job: AdminApplicationNotificationJob) do
      patch application_path(application), params: {
        token: link.raw_token,
        membership_application: {
          first_name: "Jane",
          last_name: "Member",
          street: "123 Main St",
          city: "Two Rivers",
          state: "WI",
          facebook_profile_url: "https://www.facebook.com/jane.member",
          application_notes: "I live here."
        }
      }
    end

    assert_redirected_to root_path
    assert_equal "submitted", application.reload.status
    assert_equal "pending", user.reload.status
    assert_not user.active_for_authentication?
  end
end
