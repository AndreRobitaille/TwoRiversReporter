module Admin
  class BaseController < ApplicationController
    include Authentication
    include Reauthentication

    layout "admin"

    before_action :require_admin
    before_action :require_admin_passkey
    # Last of the three deliberately. require_admin must answer first, or a
    # stranger with a mismatched context would be sent to a step-up page and
    # learn that this URL is an admin area at all.
    before_action :require_verified_context

    private
      def require_admin
        return if Current.user&.admin? && Current.user.active_for_authentication?

        redirect_to root_path, alert: "You do not have access to that section."
      end

      def require_admin_passkey
        return if Current.user.passkey_credentials.exists?

        redirect_to settings_security_path, alert: "Add a passkey before using admin tools."
      end
  end
end
