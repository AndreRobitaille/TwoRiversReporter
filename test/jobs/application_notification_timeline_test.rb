require "test_helper"
require_relative "../support/transactional_email_capture"

class ApplicationNotificationTimelineTest < ActiveJob::TestCase
  include TransactionalEmailCapture

  setup do
    @start = Time.current.change(usec: 0) + 2.hours
  end

  test "queued cooldown work delivers each pending identity without another submission" do
    travel_to @start do
      first = create_application("first")
      capture_transactional_emails do |messages|
        AdminApplicationNotificationJob.perform_later(first.id)
        perform_enqueued_jobs(only: AdminApplicationNotificationJob, at: @start)
        assert_equal [ first.user.email_address ], recipients(messages.sole)
        assert_equal @start, first.reload.admin_notification_sent_at

        travel_to @start + 30.minutes
        second = create_application("second")
        third = create_application("third")
        draft = create_application("draft", status: "email_pending")
        decided = create_application("decided", status: "approved")
        AdminApplicationNotificationJob.perform_later(second.id)
        AdminApplicationNotificationJob.perform_later(third.id)
        perform_enqueued_jobs(only: AdminApplicationNotificationJob, at: Time.current)

        assert_equal 1, messages.size
        assert_nil second.reload.admin_notification_sent_at
        assert_nil third.reload.admin_notification_sent_at
        deferred = enqueued_jobs.select { |job| job[:job] == AdminApplicationNotificationJob }
        assert_not_empty deferred, "cooldown must leave executable queued work"
        assert deferred.all? { |job| job[:at] == (@start + 1.hour + 1.second).to_f }, "inclusive cooldown expires one second after the hour"

        travel_to @start + 1.hour
        perform_enqueued_jobs(only: AdminApplicationNotificationJob, at: Time.current)
        assert_equal 1, messages.size, "no second batch at the inclusive hour boundary"
        travel_to @start + 1.hour + 1.second
        perform_enqueued_jobs(only: AdminApplicationNotificationJob, at: Time.current)
        assert_equal 2, messages.size
        assert_equal [ second.user.email_address, third.user.email_address ], recipients(messages.last)
        assert_equal 2, messages.last.data_variables.fetch(:application_count)
        [ second, third ].each { |application| assert_equal Time.current, application.reload.admin_notification_sent_at }
        [ draft, decided ].each { |application| assert_nil application.reload.admin_notification_sent_at }
        assert_equal @start, first.reload.admin_notification_sent_at
        assert_empty enqueued_jobs.select { |job| job[:job] == AdminApplicationNotificationJob }

        AdminApplicationNotificationJob.perform_later(second.id)
        perform_enqueued_jobs(only: AdminApplicationNotificationJob, at: Time.current)
        assert_equal 2, messages.size, "a duplicate invocation cannot resend a claimed identity"
        assert_empty enqueued_jobs.select { |job| job[:job] == AdminApplicationNotificationJob }
      end
    end
  end

  test "failed delivery rolls back its claim and queued retry delivers the actual batch" do
    travel_to @start do
      first = create_application("retry-first")
      second = create_application("retry-second")
      original_delivery = TransactionalEmail::Message.instance_method(:deliver_now)
      begin
        TransactionalEmail::Message.define_method(:deliver_now) { raise LoopsDelivery::DeliveryError, "Synthetic failure" }
        AdminApplicationNotificationJob.perform_later(first.id)
        perform_enqueued_jobs(only: AdminApplicationNotificationJob, at: Time.current)
      ensure
        TransactionalEmail::Message.define_method(:deliver_now, original_delivery)
      end
      assert_nil first.reload.admin_notification_sent_at
      assert_nil second.reload.admin_notification_sent_at
      retry_job = enqueued_jobs.select { |job| job[:job] == AdminApplicationNotificationJob }.sole
      assert_equal (@start + 1.minute).to_f, retry_job[:at]
      assert_equal 1, retry_job["executions"]

      capture_transactional_emails do |messages|
        travel_to @start + 1.minute
        perform_enqueued_jobs(only: AdminApplicationNotificationJob, at: Time.current)
        assert_equal [ first.user.email_address, second.user.email_address ], recipients(messages.sole)
        [ first, second ].each { |application| assert_equal Time.current, application.reload.admin_notification_sent_at }
        assert_empty enqueued_jobs.select { |job| job[:job] == AdminApplicationNotificationJob }
      end
    end
  end

  test "rollback preserves a later successful stamp and unrelated earlier notification" do
    travel_to @start do
      older = create_application("already-notified", admin_notification_sent_at: 2.hours.ago)
      first = create_application("rollback-first")
      later = create_application("later-success")
      original_delivery = TransactionalEmail::Message.instance_method(:deliver_now)
      begin
        TransactionalEmail::Message.define_method(:deliver_now) do
          later.update_columns(admin_notification_sent_at: Time.current + 1.second)
          raise LoopsDelivery::DeliveryError, "Synthetic late failure"
        end
        AdminApplicationNotificationJob.perform_later(first.id)
        perform_enqueued_jobs(only: AdminApplicationNotificationJob, at: Time.current)
      ensure
        TransactionalEmail::Message.define_method(:deliver_now, original_delivery)
      end
      assert_nil first.reload.admin_notification_sent_at
      assert_equal @start + 1.second, later.reload.admin_notification_sent_at
      assert_equal @start - 2.hours, older.reload.admin_notification_sent_at

      capture_transactional_emails do |messages|
        travel_to @start + 1.minute
        perform_enqueued_jobs(only: AdminApplicationNotificationJob, at: Time.current)
        assert_empty messages, "retry must respect the newer successful batch cooldown"
        assert_nil first.reload.admin_notification_sent_at
        travel_to @start + 1.hour + 2.seconds
        perform_enqueued_jobs(only: AdminApplicationNotificationJob, at: Time.current)
        assert_equal [ first.user.email_address ], recipients(messages.sole)
        assert_equal Time.current, first.reload.admin_notification_sent_at
        assert_equal @start + 1.second, later.reload.admin_notification_sent_at
        assert_equal @start - 2.hours, older.reload.admin_notification_sent_at
      end
    end
  end

  private

    def create_application(name, **attributes)
      user = User.create!(email_address: "notification-#{name}@example.com", status: "pending", disabled_at: Time.current)
      user.membership_applications.create!({ status: "submitted", first_name: name, last_name: "Synthetic",
        street: "123 Synthetic Street", city: "Two Rivers", state: "WI" }.merge(attributes))
    end

    def recipients(message)
      assert_equal "admin@example.com", message.email
      message.data_variables.fetch(:applicant_emails).split(", ")
    end
end
