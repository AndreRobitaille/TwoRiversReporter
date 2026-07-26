# Step-up reauthentication. Three gates, deliberately different.
#
# require_matching_context asks "is this request coming from exactly where this
# session was last verified?" — strict, no tolerance.
#
# require_matching_context_or_recent_step_up asks the same question but also
# accepts a step-up completed inside Session::REAUTH_FRESHNESS. It is the
# tolerant form, for surfaces loaded repeatedly.
#
# require_fresh_reauthentication asks "did this person prove themselves in the
# last fifteen minutes?" and ignores the context entirely. It exists because
# context matching structurally cannot catch a live session on a stolen
# unlocked laptop: same network, same browser, same everything.
#
# The two context gates are a pair and must stay a pair. Collapsing them into
# one reintroduces one of two bugs: an unbounded challenge loop in the admin
# area, or a credential surface an attacker reaches on freshness alone. Which
# one each caller needs is spelled out at its call site, and why is in the
# comment beside it.
module Reauthentication
  extend ActiveSupport::Concern

  private

    # Strict. Use where the action is a single deliberate step the user takes
    # once, so paying for a mid-action network change with one extra tap is
    # acceptable and no repeat-load loop can form.
    def require_matching_context
      return if session_context_matches?

      deny_until_reauthenticated
    end

    # Tolerant. Use where the check runs on every page load: on an egress whose
    # address rotates across /24 boundaries between requests (iCloud Private
    # Relay, carrier CGNAT, a corporate proxy pool) a strict check challenges,
    # accepts the step-up, and challenges again on the very next page — an
    # unbounded loop. Honouring a recent step-up is what lets a step-up survive
    # that churn long enough to be useful.
    def require_matching_context_or_recent_step_up
      return if session_context_matches? || Current.session&.recently_reauthenticated?

      deny_until_reauthenticated
    end

    def require_fresh_reauthentication
      return if Current.session&.recently_reauthenticated?

      deny_until_reauthenticated
    end

    def session_context_matches?
      SessionContext.from_request(request).matches?(Current.session)
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
