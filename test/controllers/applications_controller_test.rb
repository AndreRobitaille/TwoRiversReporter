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

  test "application start is rate limited" do
    user = User.create!(email_address: "rate@example.com", password: "password123", password_confirmation: "password123", status: "pending")
    original_cache = Rails.cache

    begin
      Rails.cache = ActiveSupport::Cache::MemoryStore.new

      10.times do
        post applications_path, params: { email_address: user.email_address }
        assert_redirected_to new_application_path
      end

      post applications_path, params: { email_address: user.email_address }

      assert_redirected_to new_application_path
      assert_equal "Try again later.", flash[:alert]
    ensure
      Rails.cache = original_cache
    end
  end

  test "application start does not mutate active users or create membership applications for them" do
    user = User.create!(email_address: "active@example.com", password: "password123", password_confirmation: "password123", status: "active")

    assert_no_difference("MembershipApplication.count") do
      post applications_path, params: { email_address: user.email_address.upcase }
    end

    assert_equal "active", user.reload.status
    assert_predicate user.disabled_at, :blank?
    assert_redirected_to new_application_path
    assert_equal "Check your email for the application link.", flash[:notice]
  end

  test "application start does not mutate rejected users or create membership applications for them" do
    user = User.create!(email_address: "rejected@example.com", password: "password123", password_confirmation: "password123", status: "rejected")

    assert_no_difference("MembershipApplication.count") do
      post applications_path, params: { email_address: user.email_address }
    end

    assert_equal "rejected", user.reload.status
    assert_predicate user.disabled_at, :blank?
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

  test "application token cannot render another applicant's application" do
    user_a = User.create!(email_address: "a@example.com", password: "password123", password_confirmation: "password123", status: "pending", disabled_at: Time.current)
    user_b = User.create!(email_address: "b@example.com", password: "password123", password_confirmation: "password123", status: "pending", disabled_at: Time.current)
    application_b = user_b.membership_applications.create!(status: "email_pending")
    link_a = MagicLink.create_for!(user_a, purpose: "application")

    get edit_application_path(application_b, token: link_a.raw_token)

    assert_redirected_to new_application_path
    assert_equal "That application link is invalid or expired. Please request a new one.", flash[:alert]
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

  test "submitted application cannot be edited or resubmitted through an outstanding link" do
    user = User.create!(email_address: "repeat@example.com", password: "password123", password_confirmation: "password123", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link_a = MagicLink.create_for!(user, purpose: "application")
    link_b = MagicLink.create_for!(user, purpose: "application")

    assert_enqueued_with(job: AdminApplicationNotificationJob) do
      patch application_path(application), params: {
        token: link_a.raw_token,
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

    assert_equal "submitted", application.reload.status
    assert_equal "Jane", application.first_name

    assert_no_enqueued_jobs do
      get edit_application_path(application, token: link_b.raw_token)
    end

    assert_redirected_to new_application_path
    assert_equal "That application link is invalid or expired. Please request a new one.", flash[:alert]

    assert_no_enqueued_jobs do
      patch application_path(application), params: {
        token: link_b.raw_token,
        membership_application: {
          first_name: "Changed",
          last_name: "Name",
          street: "456 Elm St",
          city: "Kohler",
          state: "WI",
          facebook_profile_url: "https://www.facebook.com/changed",
          application_notes: "Different."
        }
      }
    end

    assert_redirected_to new_application_path
    assert_equal "submitted", application.reload.status
    assert_equal "Jane", application.first_name
  end

  test "restarting a submitted application does not create a second application record" do
    user = User.create!(email_address: "restart@example.com", password: "password123", password_confirmation: "password123", status: "pending", disabled_at: Time.current)

    assert_difference("MembershipApplication.count", 1) do
      post applications_path, params: { email_address: user.email_address }
    end

    application = user.membership_applications.order(:created_at).last
    application.update!(status: "submitted", first_name: "Jane", last_name: "Member", city: "Two Rivers", state: "WI")

    assert_no_difference("MembershipApplication.count") do
      post applications_path, params: { email_address: user.email_address }
    end

    assert_redirected_to new_application_path
    assert_equal "Check your email for the application link.", flash[:notice]
  end

  test "application token cannot submit another applicant's application" do
    user_a = User.create!(email_address: "submit-a@example.com", password: "password123", password_confirmation: "password123", status: "pending", disabled_at: Time.current)
    user_b = User.create!(email_address: "submit-b@example.com", password: "password123", password_confirmation: "password123", status: "pending", disabled_at: Time.current)
    application_b = user_b.membership_applications.create!(status: "email_pending")
    link_a = MagicLink.create_for!(user_a, purpose: "application")

    patch application_path(application_b), params: {
      token: link_a.raw_token,
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

    assert_redirected_to new_application_path
    assert_equal "That application link is invalid or expired. Please request a new one.", flash[:alert]
    assert_equal "email_pending", application_b.reload.status
    assert_equal "pending", user_b.reload.status
    assert_equal 0, ActionMailer::Base.deliveries.size
  end
end
