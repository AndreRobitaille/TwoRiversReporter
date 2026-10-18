require "application_system_test_case"

class ApplicationNotificationJourneysTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  test "completed application queues its notification and the same answers reach admin review" do
    email = "browser-application-notification@example.com"
    capture_transactional_emails do |messages|
      visit new_application_path
      fill_in "Email address", with: email
      click_button "Send application link"
      assert_text "Check your email"
      assert_equal email, messages.sole.email
      user = User.find_by!(email_address: email)
      application = user.membership_applications.sole
      link = user.magic_links.sole
      visit messages.sole.data_variables.fetch(:application_url)
      assert_field "First name"
      assert_predicate link.reload, :unused?
      assert_empty user.sessions
      fill_in "First name", with: "Distinctive"
      fill_in "Last name", with: "Resident"
      fill_in "Street address", with: "456 Synthetic Avenue"
      fill_in "City", with: "Two Rivers"
      fill_in "State", with: "WI"
      fill_in "Anything you'd like us to know", with: "Distinctive synthetic application notes"
      click_button "Submit application"
      assert_current_path submitted_applications_path
      assert_selector "h1", text: /Application received/i
      assert_equal "submitted", application.reload.status
      assert_not_nil application.submitted_at
      assert_not_nil link.reload.used_at
      assert_empty user.sessions
      assert_equal [ application.id ], enqueued_jobs.select { |job| job[:job] == AdminApplicationNotificationJob }.sole[:args]

      perform_enqueued_jobs(only: AdminApplicationNotificationJob)
      notification = messages.last
      assert_equal 2, messages.size
      assert_equal "admin@example.com", notification.email
      assert_equal 1, notification.data_variables.fetch(:application_count)
      assert_equal email, notification.data_variables.fetch(:applicant_emails)
      assert_not_nil application.reload.admin_notification_sent_at
    end

    admin = User.create!(email_address: "browser-application-reviewer@example.com", status: "active", admin: true)
    admin.passkey_credentials.create!(external_id: "application-review-eligibility", public_key: "fixture", sign_count: 0)
    sign_in_by_email(admin)
    click_link "Admin", exact: true
    within "#admin-sidebar" do
      click_link "User Accounts", exact: true
    end
    click_link email, exact: true
    assert_text email
    assert_text "Distinctive Resident"
    assert_text "456 Synthetic Avenue"
    assert_text "Distinctive synthetic application notes"
    assert_button "Approve application"
    assert_button "Deny and notify applicant"
    application = User.find_by!(email_address: email).membership_applications.sole
    assert_equal "submitted", application.status
    assert_nil application.reviewed_by_id
  end
end
