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

  test "sends fresh submitted applications in the next batch after the cooldown" do
    old_applicant = User.create!(email_address: "old@example.com", password: "password", status: "pending")
    old_app = old_applicant.membership_applications.create!(status: "submitted", first_name: "Old", last_name: "User", city: "Two Rivers", state: "WI", created_at: 2.hours.ago)

    TransactionalEmail.stub(:admin_application_notifications, Object.new.tap { |message| message.define_singleton_method(:deliver_now) {} }) do
      AdminApplicationNotificationJob.perform_now(old_app.id)
    end

    travel 61.minutes do
      fresh_applicant = User.create!(email_address: "fresh@example.com", password: "password", status: "pending")
      fresh_app = fresh_applicant.membership_applications.create!(status: "submitted", first_name: "Fresh", last_name: "User", city: "Two Rivers", state: "WI")
      deliveries = 0
      message = Object.new
      message.define_singleton_method(:deliver_now) { deliveries += 1 }

      TransactionalEmail.stub(:admin_application_notifications, message) do
        AdminApplicationNotificationJob.perform_now(fresh_app.id)
        assert_equal 1, deliveries
        assert_not_nil old_app.reload.admin_notification_sent_at
        assert_not_nil fresh_app.reload.admin_notification_sent_at
      end
    end
  end
end
