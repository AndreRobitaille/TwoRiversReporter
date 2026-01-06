module Admin
  class BaseController < ApplicationController
    include Authentication

    before_action :require_admin
    before_action :require_admin_mfa

    private
      def require_admin
        return if Current.user&.admin?

        terminate_session if Current.session
        redirect_to new_session_path, alert: "Not authorized."
      end

      def require_admin_mfa
        return if Current.user&.totp_enabled?

        terminate_session if Current.session
        redirect_to new_session_path, alert: "Multi-factor authentication is required."
      end
  end
end
