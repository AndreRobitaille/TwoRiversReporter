class AdminApplicationNotificationJob < ApplicationJob
  queue_as :default

  def perform(membership_application_id)
    applications = nil
    batch_sent_at = nil

    MembershipApplication.transaction do
      lock_admin_scope!
      return if cooldown_active?

      applications = MembershipApplication.lock.where(status: "submitted", admin_notification_sent_at: nil)
                                         .order(:created_at)
                                         .to_a
      return if applications.empty?
    end

    batch_sent_at = Time.current
    MembershipApplication.transaction do
      lock_admin_scope!
      return if cooldown_active?

      claimed_ids = MembershipApplication.where(id: applications.map(&:id), status: "submitted", admin_notification_sent_at: nil).pluck(:id)
      return if claimed_ids.empty?

      MembershipApplication.where(id: claimed_ids).update_all(admin_notification_sent_at: batch_sent_at)
      applications = MembershipApplication.where(id: claimed_ids).order(:created_at).to_a
    end

    message = TransactionalEmail.admin_application_notifications(applications)
    message.deliver_now
  rescue StandardError
    MembershipApplication.where(id: applications&.map(&:id), admin_notification_sent_at: batch_sent_at).update_all(admin_notification_sent_at: nil) if batch_sent_at.present?
    raise
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
