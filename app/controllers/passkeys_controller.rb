class PasskeysController < ApplicationController
  include Authentication
  include WebauthnVerification

  allow_unauthenticated_access only: %i[authentication_options authentication]
  rate_limit to: 10, within: 3.minutes, only: %i[registration_options registration authentication_options authentication], with: -> { head :too_many_requests }

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
