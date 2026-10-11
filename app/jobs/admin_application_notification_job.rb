class AdminApplicationNotificationJob < ApplicationJob
  queue_as :default
  retry_on LoopsDelivery::DeliveryError, wait: 1.minute, attempts: 5, jitter: 0

  def perform(membership_application_id)
    applications = nil
    batch_sent_at = nil

    MembershipApplication.transaction do
      lock_admin_scope!
      return if defer_for_cooldown(membership_application_id)

      applications = MembershipApplication.lock.where(status: "submitted", admin_notification_sent_at: nil)
                                         .order(:created_at)
                                         .to_a
      return if applications.empty?
    end

    batch_sent_at = Time.current
    MembershipApplication.transaction do
      lock_admin_scope!
      return if defer_for_cooldown(membership_application_id)

      claimed_ids = MembershipApplication.where(id: applications.map(&:id), status: "submitted", admin_notification_sent_at: nil).pluck(:id)
      return if claimed_ids.empty?

      applications = MembershipApplication.lock.where(id: claimed_ids, status: "submitted", admin_notification_sent_at: nil)
                                          .order(:created_at)
                                          .to_a
      return if applications.empty?

      applications.each { |application| application.update_columns(admin_notification_sent_at: batch_sent_at) }
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

    def defer_for_cooldown(membership_application_id)
      last_sent_at = MembershipApplication.where.not(admin_notification_sent_at: nil).maximum(:admin_notification_sent_at)
      return false unless last_sent_at.present? && last_sent_at >= 1.hour.ago

      if MembershipApplication.exists?(status: "submitted", admin_notification_sent_at: nil)
        # The existing cooldown includes the exact hour boundary. A duplicate
        # job is harmless: claims are serialized and rechecked before delivery.
        self.class.set(wait_until: last_sent_at + 1.hour + 1.second).perform_later(membership_application_id)
      end
      true
    end
end
