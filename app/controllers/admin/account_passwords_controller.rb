module Admin
  class AccountPasswordsController < BaseController
    def edit
    end

    def update
      unless Current.user.authenticate(params[:current_password])
        redirect_to edit_account_password_path, alert: "Current password is incorrect."
        return
      end

      if Current.user.update(password_params)
        Current.user.sessions.destroy_all
        start_new_session_for Current.user
        redirect_to admin_root_path, notice: "Password updated."
      else
        redirect_to edit_account_password_path, alert: "Passwords did not match."
      end
    end

    private
      def password_params
        params.permit(:password, :password_confirmation)
      end
  end
end
