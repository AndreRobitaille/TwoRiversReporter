class AdminApplicationNotificationJob < ApplicationJob
  queue_as :default

  def perform(membership_application_id)
    return if sent_within_hour?(membership_application_id)

    applications = MembershipApplication.where(status: "submitted", admin_notification_sent_at: nil)
                                       .where("created_at <= ?", 1.hour.ago)
                                       .order(:created_at)

    applications = applications.to_a
    return if applications.empty?

    TransactionalEmail.admin_application_notifications(applications).deliver_now
    MembershipApplication.where(id: applications.map(&:id)).update_all(admin_notification_sent_at: Time.current)
  end

  private

    def sent_within_hour?(membership_application_id)
      application = MembershipApplication.find_by(id: membership_application_id)
      return false unless application&.admin_notification_sent_at

      application.admin_notification_sent_at >= 1.hour.ago
    end
end
