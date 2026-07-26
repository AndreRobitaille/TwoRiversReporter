class PasskeysController < ApplicationController
  include Authentication
  include WebauthnVerification
  include Reauthentication

  allow_unauthenticated_access only: %i[authentication_options authentication]
  rate_limit to: 10, within: 3.minutes, only: %i[registration_options registration authentication_options authentication], with: -> { head :too_many_requests }

  # Adding a passkey is how a stolen session becomes durable independent
  # access — there is no password to change to evict it afterwards. Removing
  # one is the mirror threat: strip an admin's only credential and
  # require_admin_passkey locks them out of their own site.
  before_action :require_fresh_reauthentication, only: %i[registration_options registration destroy]

  # The strict context gate, and deliberately not the tolerant one the admin
  # boundary uses. Freshness alone is already required above, so a gate that
  # also passed on freshness would add nothing: a cookie stolen and replayed
  # from another network within fifteen minutes of the victim's sign-in would
  # register an attacker's credential with nothing tripped. Changing a
  # credential is one deliberate action, not a page loaded repeatedly, so one
  # extra tap after a network change is an acceptable cost and no challenge
  # loop can form here.
  #
  # Not applied to authentication_options/authentication: those are the
  # unauthenticated sign-in path, where there is no session to match against.
  before_action :require_matching_context, only: %i[registration_options registration destroy]

  before_action :load_current_user_credential, only: %i[update destroy]
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  def registration_options
    credential_ids = current_user.passkey_credentials.pluck(:external_id)
    options = webauthn_options_for_create(
      user: { id: current_user.webauthn_id, name: current_user.email_address, display_name: current_user.email_address },
      authenticator_selection: { resident_key: "required", user_verification: "required" },
      exclude: credential_ids
    )

    session[:passkey_registration_challenge] = options.challenge
    render json: options
  end

  def registration
    credential = verified_create_credential
    return if performed?
    passkey = current_user.passkey_credentials.new(
      external_id: credential.id,
      public_key: credential.public_key,
      sign_count: credential.sign_count
    )
    passkey.save!
    render json: { success: true, redirect_to: settings_security_url }
  end

  def authentication_options
    options = webauthn_options_for_get(user_verification: :required)
    session[:passkey_authentication_challenge] = options.challenge
    render json: options
  end

  def authentication
    credential = verified_get_credential(params[:credential], challenge_key: :passkey_authentication_challenge)
    return if performed?
    passkey = PasskeyCredential.includes(:user).find_by(external_id: credential.id)
    return head :unauthorized unless passkey.user.active_for_authentication?

    passkey.update!(sign_count: credential.sign_count, last_used_at: Time.current)
    start_new_session_for(passkey.user)
    render json: { success: true, redirect_to: after_authentication_url }
  end

  def update
    if @passkey_credential.update(passkey_params)
      redirect_to settings_security_path, status: :see_other
    else
      render json: { errors: @passkey_credential.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @passkey_credential.destroy!
    redirect_to settings_security_path, status: :see_other
  rescue User::LastAdminError
    redirect_to settings_security_path,
      alert: "At least one active admin with a passkey must remain.",
      status: :see_other
  end

  private

    def current_user
      Current.user
    end

    def load_current_user_credential
      @passkey_credential = current_user.passkey_credentials.find(params[:id])
    end

    def passkey_params
      params.fetch(:passkey_credential, {}).permit(:nickname)
    end

    def verified_create_credential
      credential = webauthn_credential_from_create(params[:credential])
      return if performed?
      credential.verify(
        session.delete(:passkey_registration_challenge),
        user_verification: true
      )
      credential
    rescue WebAuthn::Error
      head :unprocessable_entity
      nil
    end

    def webauthn_options_for_create(**kwargs)
      WebAuthn::Credential.options_for_create(**kwargs)
    end

    def webauthn_options_for_get(**kwargs)
      WebAuthn::Credential.options_for_get(**kwargs)
    end

    def webauthn_credential_from_create(*args, **kwargs)
      WebAuthn::Credential.from_create(*args, **kwargs)
    rescue NoMethodError, TypeError, ArgumentError
      head :unprocessable_entity
      nil
    end

    def render_not_found
      head :not_found
    end
end
