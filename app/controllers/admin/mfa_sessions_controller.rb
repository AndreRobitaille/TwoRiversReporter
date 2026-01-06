module Admin
  class MfaSessionsController < ApplicationController
    include Authentication

    allow_unauthenticated_access
    rate_limit to: 20, within: 5.minutes, only: :create, with: -> { redirect_to new_mfa_session_path, alert: "Try again later." }

    before_action :set_user

    def new
    end

    def create
      if @user.valid_totp_code?(params[:code]) || @user.consume_recovery_code(params[:code])
        session.delete(:pending_mfa_user_id)
        start_new_session_for @user
        redirect_to after_authentication_url
      else
        redirect_to new_mfa_session_path, alert: "Invalid code."
      end
    end

    private
      def set_user
        @user = User.find_by(id: session[:pending_mfa_user_id])
        return if @user&.admin? && @user.totp_enabled?

        redirect_to new_session_path, alert: "Please sign in again."
      end
  end
end
