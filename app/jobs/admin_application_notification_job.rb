class AdminApplicationNotificationJob < ApplicationJob
  queue_as :default

  def perform(membership_application_id)
    applications = nil

    MembershipApplication.transaction do
      lock_admin_scope!
      return if cooldown_active?

      applications = MembershipApplication.lock.where(status: "submitted", admin_notification_sent_at: nil)
                                         .order(:created_at)
                                         .to_a
      return if applications.empty?

      batch_sent_at = Time.current
      MembershipApplication.where(id: applications.map(&:id)).update_all(admin_notification_sent_at: batch_sent_at)
      applications.each { |application| application.admin_notification_sent_at = batch_sent_at }
    end

    TransactionalEmail.admin_application_notifications(applications).deliver_now
  end

  private

    def lock_admin_scope!
      User.order(:id).lock.first!
    end

    def cooldown_active?
      last_sent_at = MembershipApplication.where.not(admin_notification_sent_at: nil).maximum(:admin_notification_sent_at)
      last_sent_at.present? && last_sent_at >= 1.hour.ago
    end
end
