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
      application.destroy!

      redirect_to user_path(user), notice: "Application deleted."
    end
  end
end
