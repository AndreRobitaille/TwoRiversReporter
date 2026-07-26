module Settings
  class SecurityController < ApplicationController
    include Authentication
    include Reauthentication

    def show
      @passkey_credentials = Current.user.passkey_credentials.order(created_at: :desc, id: :desc)
      @known_contexts = Current.user.known_contexts.order(last_seen_at: :desc)

      # PasskeysController gates add and remove on a fresh step-up *and* an
      # exactly matching context. This page-level gate has to ask the same
      # question, or it renders an "Add a passkey" button whose endpoint answers
      # 403 and passkey_controller.js reports a misleading error. A step-up
      # rewrites the recorded context and stamps freshness in one operation, so
      # the link offered instead resolves both halves at once.
      @passkey_management_unlocked = Current.session&.recently_reauthenticated? && session_context_matches?
    end
  end
end
