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
    #
    # The tolerant context gate, not the strict one. This runs on every admin
    # page load, so on an egress that rotates its address between requests a
    # strict check would challenge, accept the step-up, and challenge again on
    # the next page forever. A step-up has to buy the admin a working window,
    # not a single request. The credential surface in PasskeysController makes
    # the opposite trade for the opposite reason — see the comment there.
    before_action :require_matching_context_or_recent_step_up

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
