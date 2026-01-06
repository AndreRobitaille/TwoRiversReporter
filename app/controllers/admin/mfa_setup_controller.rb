module Admin
  class MfaSetupController < ApplicationController
    include Authentication

    allow_unauthenticated_access

    before_action :set_user

    def show
      @user.ensure_totp_secret!
    end

    def create
      @user.ensure_totp_secret!

      unless @user.valid_totp_code?(params[:code])
        redirect_to mfa_setup_path, alert: "Invalid code."
        return
      end

      @user.update!(totp_enabled: true)
      recovery_codes = @user.regenerate_recovery_codes!

      session.delete(:pending_mfa_setup_user_id)
      start_new_session_for @user
      session[:new_recovery_codes] = recovery_codes

      redirect_to recovery_codes_path
    end

    private
      def set_user
        @user = User.find_by(id: session[:pending_mfa_setup_user_id])
        return if @user&.admin?

        redirect_to new_session_path, alert: "Please sign in again."
      end
  end
end
