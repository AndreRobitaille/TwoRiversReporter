class AdminApplicationNotificationJob < ApplicationJob
  queue_as :default

  def perform(membership_application_id)
    MembershipApplication.find_by(id: membership_application_id)
  end
end
