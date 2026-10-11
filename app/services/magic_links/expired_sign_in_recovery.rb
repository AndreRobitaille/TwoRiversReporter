module MagicLinks
  class ExpiredSignInRecovery
    class Throttled < StandardError; end

    def initialize(token)
      @token = token
    end

    def call
      source = MagicLink.expired_sign_in_link(@token)
      raise MagicLink::InvalidToken unless source

      attempt = nil
      replacement = nil
      user = source.user
      user.with_lock do
        raise MagicLink::InvalidToken unless MagicLink.expired_sign_in_link(@token)&.id == source.id
        raise Throttled if SignInAttempt.throttled?(user.email_address)

        attempt = SignInAttempt.record!(user.email_address)
        replacement = MagicLink.create_for!(user, purpose: "sign_in")
      end

      TransactionalEmail.magic_link(user, replacement).deliver_now
      replacement
    rescue StandardError
      MagicLink.where(id: replacement.id, used_at: nil).delete_all if replacement
      attempt&.destroy!
      raise
    end
  end
end
