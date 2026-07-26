module Admin
  class MembershipApplicationsController < BaseController
    before_action :require_fresh_reauthentication, only: :destroy

    # Irreversible removal of a single application. The account it belongs to is
    # left alone: an admin deleting a duplicate or spam submission usually still
    # wants the user row (and its status) to stay as it is. Deleting the whole
    # account is a separate, explicit action.
    def destroy
      application = MembershipApplication.find(params[:id])
      user = application.user
      AuditEvent.record!(actor: Current.user, action: "membership_application.destroy",
        subject: application, label: user.email_address, request: request)
      application.destroy!

      redirect_to user_path(user), notice: "Application deleted."
    end
  end
end
