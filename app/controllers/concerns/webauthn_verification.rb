# The WebAuthn "get" ceremony, shared by passkey sign-in and by step-up
# reauthentication. The two differ only in which session key holds the
# challenge, so that is the parameter.
#
# Every failure path renders a response and returns nil. Callers must check
# `performed?` before using the return value.
module WebauthnVerification
  extend ActiveSupport::Concern

  private

    def webauthn_credential_from_get(payload)
      WebAuthn::Credential.from_get(payload)
    rescue NoMethodError, TypeError, ArgumentError
      head :unauthorized
      nil
    end

    def verified_get_credential(payload, challenge_key:)
      credential = webauthn_credential_from_get(payload)
      return if performed?

      passkey = PasskeyCredential.find_by(external_id: credential.id)
      return head :unauthorized unless passkey

      credential.verify(
        session.delete(challenge_key),
        public_key: passkey.public_key,
        sign_count: passkey.sign_count,
        user_verification: true
      )
      credential
    rescue WebAuthn::Error
      head :unauthorized
      nil
    end
end
