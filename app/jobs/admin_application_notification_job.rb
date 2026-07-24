class AdminApplicationNotificationJob < ApplicationJob
  queue_as :default

  def perform(membership_application_id)
    return if cooldown_active?

    applications = MembershipApplication.where(status: "submitted", admin_notification_sent_at: nil)
                                       .order(:created_at)

    applications = applications.to_a
    return if applications.empty?

    TransactionalEmail.admin_application_notifications(applications).deliver_now
    MembershipApplication.where(id: applications.map(&:id)).update_all(admin_notification_sent_at: Time.current)
  end

  private

    def cooldown_active?
      MembershipApplication.where(status: "submitted")
                           .where("admin_notification_sent_at >= ?", 1.hour.ago)
                           .exists?
    end
end
