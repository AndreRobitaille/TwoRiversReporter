require "test_helper"

class AdminApplicationNotificationJobTest < ActiveSupport::TestCase
  test "sends one batch for submitted unnotified applications and does not resend within one hour" do
    applicant_one = User.create!(email_address: "one@example.com", password: "password", status: "pending")
    applicant_two = User.create!(email_address: "two@example.com", password: "password", status: "pending")
    app_one = applicant_one.membership_applications.create!(status: "submitted", first_name: "One", last_name: "User", city: "Two Rivers", state: "WI", created_at: 2.hours.ago)
    app_two = applicant_two.membership_applications.create!(status: "submitted", first_name: "Two", last_name: "User", city: "Two Rivers", state: "WI", created_at: 2.hours.ago)

    deliveries = 0
    message = Object.new
    message.define_singleton_method(:deliver_now) { deliveries += 1 }

    TransactionalEmail.stub(:admin_application_notifications, message) do
      AdminApplicationNotificationJob.perform_now(app_one.id)
      assert_equal 1, deliveries
      assert_not_nil app_one.reload.admin_notification_sent_at
      assert_not_nil app_two.reload.admin_notification_sent_at

      AdminApplicationNotificationJob.perform_now(app_one.id)
      assert_equal 1, deliveries
    end
  end
end
