require "test_helper"

class AdminApplicationNotificationJobTest < ActiveSupport::TestCase
  test "sends one batch for submitted unnotified applications and does not resend within one hour" do
    travel 2.hours do
      applicant_one = User.create!(email_address: "one@example.com", password: "password", status: "pending")
      applicant_two = User.create!(email_address: "two@example.com", password: "password", status: "pending")
      app_one = applicant_one.membership_applications.create!(status: "submitted", first_name: "One", last_name: "User", city: "Two Rivers", state: "WI")
      app_two = applicant_two.membership_applications.create!(status: "submitted", first_name: "Two", last_name: "User", city: "Two Rivers", state: "WI")

      assert_difference -> { MembershipApplication.where.not(admin_notification_sent_at: nil).count }, 2 do
        AdminApplicationNotificationJob.perform_now(app_one.id)
      end

      assert_not_nil app_one.reload.admin_notification_sent_at
      assert_not_nil app_two.reload.admin_notification_sent_at

      assert_no_difference -> { MembershipApplication.where.not(admin_notification_sent_at: nil).count } do
        AdminApplicationNotificationJob.perform_now(app_one.id)
      end
    end
  end

  test "does not send a second batch for a new submitted application within one hour" do
    travel 2.hours do
      first_applicant = User.create!(email_address: "first@example.com", password: "password", status: "pending")
      first_app = first_applicant.membership_applications.create!(status: "submitted", first_name: "First", last_name: "User", city: "Two Rivers", state: "WI")

      assert_difference -> { MembershipApplication.where.not(admin_notification_sent_at: nil).count }, 1 do
        AdminApplicationNotificationJob.perform_now(first_app.id)
      end
    end

    travel 2.hours + 30.minutes do
      second_applicant = User.create!(email_address: "second@example.com", password: "password", status: "pending")
      second_app = second_applicant.membership_applications.create!(status: "submitted", first_name: "Second", last_name: "User", city: "Two Rivers", state: "WI")

      assert_no_difference -> { MembershipApplication.where.not(admin_notification_sent_at: nil).count } do
        AdminApplicationNotificationJob.perform_now(second_app.id)
      end
      assert_nil second_app.reload.admin_notification_sent_at
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
      message.define_singleton_method(:deliver_now) do
        deliveries += 1
        raise "fresh batch not claimed" if fresh_app.reload.admin_notification_sent_at.nil?
        raise "cooldown stamp missing" if old_app.reload.admin_notification_sent_at.nil?
      end

      TransactionalEmail.stub(:admin_application_notifications, message) do
        AdminApplicationNotificationJob.perform_now(fresh_app.id)
        assert_equal 1, deliveries
        assert_not_nil old_app.reload.admin_notification_sent_at
        assert_not_nil fresh_app.reload.admin_notification_sent_at
      end
    end
  end

  test "leaves submitted applications retryable when message construction raises" do
    travel 2.hours do
      applicant = User.create!(email_address: "retry-build@example.com", password: "password", status: "pending")
      application = applicant.membership_applications.create!(status: "submitted", first_name: "Retry", last_name: "Build", city: "Two Rivers", state: "WI")

      original = TransactionalEmail.method(:admin_application_notifications)
      begin
        TransactionalEmail.define_singleton_method(:admin_application_notifications) { |*| raise "boom" }
        assert_raises(RuntimeError) { AdminApplicationNotificationJob.perform_now(application.id) }
      ensure
        TransactionalEmail.define_singleton_method(:admin_application_notifications, original)
      end

      assert_nil application.reload.admin_notification_sent_at
    end
  end

  test "leaves submitted applications retryable when delivery raises" do
    travel 2.hours do
      applicant = User.create!(email_address: "retry-delivery@example.com", password: "password", status: "pending")
      application = applicant.membership_applications.create!(status: "submitted", first_name: "Retry", last_name: "Delivery", city: "Two Rivers", state: "WI")

      original = TransactionalEmail.method(:admin_application_notifications)
      begin
        message = Object.new
        message.define_singleton_method(:deliver_now) { raise "delivery failed" }
        TransactionalEmail.define_singleton_method(:admin_application_notifications) { |*| message }

        assert_raises(RuntimeError) { AdminApplicationNotificationJob.perform_now(application.id) }
      ensure
        TransactionalEmail.define_singleton_method(:admin_application_notifications, original)
      end

      assert_nil application.reload.admin_notification_sent_at
    end
  end

  test "keeps cooldown active when a previously notified application is approved within the hour" do
    notified_applicant = User.create!(email_address: "notified@example.com", password: "password", status: "pending")
    notified_app = notified_applicant.membership_applications.create!(
      status: "approved",
      first_name: "Notified",
      last_name: "User",
      city: "Two Rivers",
      state: "WI",
      admin_notification_sent_at: Time.current
    )

    travel 30.minutes do
      fresh_applicant = User.create!(email_address: "fresh-cooldown@example.com", password: "password", status: "pending")
      fresh_app = fresh_applicant.membership_applications.create!(status: "submitted", first_name: "Fresh", last_name: "User", city: "Two Rivers", state: "WI")

      TransactionalEmail.stub(:admin_application_notifications, Object.new.tap { |message| message.define_singleton_method(:deliver_now) {} }) do
        AdminApplicationNotificationJob.perform_now(fresh_app.id)
      end
      assert_nil fresh_app.reload.admin_notification_sent_at
      assert_equal "approved", notified_app.reload.status
    end
  end

end
