class PasskeysController < ApplicationController
  include Authentication

  allow_unauthenticated_access only: %i[authentication_options authentication]

  before_action :load_current_user_credential, only: %i[update destroy]
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  def registration_options
    credential_ids = current_user.passkey_credentials.pluck(:external_id)
    options = webauthn_options_for_create(
      user: { id: current_user.webauthn_id, name: current_user.email_address, display_name: current_user.email_address },
      resident_key: :required,
      user_verification: :required,
      exclude: credential_ids
    )

    session[:webauthn_registration_challenge] = options.challenge
    render json: options
  end

  def registration
    credential = verified_create_credential
    passkey = current_user.passkey_credentials.new(
      external_id: credential.id,
      public_key: credential.public_key,
      sign_count: credential.sign_count,
      nickname: credential.nickname
    )
    passkey.save!
    session.delete(:webauthn_registration_challenge)
    render json: { success: true }
  end

  def authentication_options
    options = webauthn_options_for_get(user_verification: :required)
    session[:webauthn_authentication_challenge] = options.challenge
    render json: options
  end

  def authentication
    credential = verified_get_credential
    passkey = PasskeyCredential.includes(:user).find_by(external_id: credential.id)
    return head :not_found unless passkey
    return head :unauthorized unless passkey.user.active_for_authentication?

    passkey.update!(sign_count: credential.sign_count, last_used_at: Time.current)
    start_new_session_for(passkey.user)
    session.delete(:webauthn_authentication_challenge)
    render json: { success: true }
  end

  def update
    if @passkey_credential.update(passkey_params)
      render json: { success: true }
    else
      render json: { errors: @passkey_credential.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @passkey_credential.destroy!
    head :no_content
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
      webauthn_credential_from_create(params[:credential], session[:webauthn_registration_challenge], user_verification: :required)
    end

    def verified_get_credential
      webauthn_credential_from_get(params[:credential], session[:webauthn_authentication_challenge], user_verification: :required)
    end

    def webauthn_options_for_create(**kwargs)
      WebAuthn::Credential.options_for_create(**kwargs)
    end

    def webauthn_options_for_get(**kwargs)
      WebAuthn::Credential.options_for_get(**kwargs)
    end

    def webauthn_credential_from_create(*args, **kwargs)
      WebAuthn::Credential.from_create(*args, **kwargs)
    end

    def webauthn_credential_from_get(*args, **kwargs)
      WebAuthn::Credential.from_get(*args, **kwargs)
    end

    def render_not_found
      head :not_found
    end
end
