# Step-up reauthentication. Two gates, deliberately different.
#
# require_verified_context asks "is this session being used where it was last
# used?" and is applied at the admin boundary, so every admin screen is covered
# including ones written later.
#
# require_fresh_reauthentication asks "did this person prove themselves in the
# last fifteen minutes?" and ignores the context entirely. It exists because
# context matching structurally cannot catch a live session on a stolen
# unlocked laptop: same network, same browser, same everything.
module Reauthentication
  extend ActiveSupport::Concern

  private

    def require_verified_context
      return if SessionContext.from_request(request).matches?(Current.session)

      deny_until_reauthenticated
    end

    def require_fresh_reauthentication
      return if Current.session&.recently_reauthenticated?

      deny_until_reauthenticated
    end

    def deny_until_reauthenticated
      # A 302 to an HTML page is not a usable answer to a fetch() that asked for
      # JSON. passkey_controller.js would read the redirect body as a malformed
      # options response and report the wrong error entirely.
      return head :forbidden if request.format.json?

      # Only a GET is worth returning to. Storing a POST url would send the user
      # back to a route that does not answer GET once they have reauthenticated.
      session[:return_to_after_authenticating] = request.get? ? request.url : request.referer
      redirect_to new_reauthentication_path
    end
end
