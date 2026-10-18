module Settings
  class SecurityController < ApplicationController
    include Authentication
    include Reauthentication

    def show
      @passkey_credentials = Current.user.passkey_credentials.order(created_at: :desc, id: :desc)
      @known_contexts = Current.user.known_contexts.order(last_seen_at: :desc)

      # The page offers controls after fresh proof in the session's anchor.
      # Endpoints also accept a remembered network/browser pair. Preserve this
      # approved distinction; step-up refreshes the anchor before showing controls.
      @passkey_management_unlocked = Current.session&.recently_reauthenticated? && session_context_matches?
    end
  end
end
