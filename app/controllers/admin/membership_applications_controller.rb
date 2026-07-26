module Admin
  class MembershipApplicationsController < BaseController
    before_action :require_fresh_reauthentication, only: :destroy
    # Strict, not the tolerant admin-boundary gate — see the same comment on
    # Admin::UsersController. Deleting an application is irreversible and
    # single-shot, so an extra tap on a drifted context costs nothing a loop
    # would come from, and buys back the replayed-cookie case the tolerant
    # grace would otherwise let through.
    before_action :require_matching_context, only: :destroy

    # Irreversible removal of a single application. The account it belongs to is
    # left alone: an admin deleting a duplicate or spam submission usually still
    # wants the user row (and its status) to stay as it is. Deleting the whole
    # account is a separate, explicit action.
    def destroy
      application = MembershipApplication.find(params[:id])
      user = application.user
      # Same reasoning as Admin::UsersController#destroy: record! and
      # destroy! must share one transaction, or a future failure inside
      # destroy! can't unwind an insert that already committed on its own.
      ApplicationRecord.transaction do
        AuditEvent.record!(actor: Current.user, action: "membership_application.destroy",
          subject: application, label: user.email_address, request: request)
        application.destroy!
      end

      redirect_to user_path(user), notice: "Application deleted."
    end
  end
end
