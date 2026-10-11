require "test_helper"
require "timeout"

class ApplicationNotificationConcurrencyTest < ActiveJob::TestCase
  self.use_transactional_tests = false

  test "overlapping persisted claims defer new work and never duplicate the in-flight batch" do
    users = []
    messages = Queue.new
    delivering = Queue.new
    release_delivery = Queue.new
    original_delivery = TransactionalEmail::Message.instance_method(:deliver_now)
    worker = nil

    travel_to Time.current.change(usec: 0) + 2.hours do
      first = create_application("in-flight", users)
      second = nil
      TransactionalEmail::Message.define_method(:deliver_now) do
        messages << self
        if data_variables.fetch(:applicant_emails).include?("in-flight")
          delivering << true
          Timeout.timeout(10) { release_delivery.pop }
        end
        true
      end
      AdminApplicationNotificationJob.perform_later(first.id)
      serialized_job = enqueued_jobs.shift
      worker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { ActiveJob::Base.execute(serialized_job) }
      end
      Timeout.timeout(10) { delivering.pop }
      assert_equal Time.current, first.reload.admin_notification_sent_at, "the first claim is committed before delivery"

      second = create_application("arrived-during-send", users)
      AdminApplicationNotificationJob.perform_later(second.id)
      AdminApplicationNotificationJob.perform_later(first.id)
      perform_enqueued_jobs(only: AdminApplicationNotificationJob, at: Time.current)
      assert_equal 1, messages.size
      assert_nil second.reload.admin_notification_sent_at
      assert_not_empty enqueued_jobs.select { |job| job[:job] == AdminApplicationNotificationJob }
      release_delivery << true
      Timeout.timeout(10) { worker.value }
      first_message = messages.pop
      assert_equal first.user.email_address, first_message.data_variables.fetch(:applicant_emails)
      assert_equal 1, first_message.data_variables.fetch(:application_count)

      travel 1.hour + 1.second
      perform_enqueued_jobs(only: AdminApplicationNotificationJob, at: Time.current)
      assert_equal 1, messages.size
      second_message = messages.pop
      assert_equal second.user.email_address, second_message.data_variables.fetch(:applicant_emails)
      assert_equal 1, second_message.data_variables.fetch(:application_count)
      assert_equal Time.current, second.reload.admin_notification_sent_at
      assert_empty enqueued_jobs.select { |job| job[:job] == AdminApplicationNotificationJob }
    end
  ensure
    release_delivery << true if release_delivery
    worker&.join(10)
    TransactionalEmail::Message.define_method(:deliver_now, original_delivery) if original_delivery
    users&.each { |user| user.destroy! }
  end

  private

    def create_application(name, users)
      user = User.create!(email_address: "concurrent-#{name}@example.com", status: "pending", disabled_at: Time.current)
      users << user
      user.membership_applications.create!(status: "submitted", first_name: name, last_name: "Synthetic",
        street: "123 Synthetic Street", city: "Two Rivers", state: "WI")
    end
end
