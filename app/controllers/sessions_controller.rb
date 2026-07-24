class SessionsController < ApplicationController
  include Authentication

  allow_unauthenticated_access only: %i[new create magic_link resend_expired_magic_link]
  rate_limit to: 10, within: 3.minutes, only: %i[create magic_link resend_expired_magic_link], with: -> { redirect_to new_public_session_path, alert: "Try again later." }

  def new
  end

  def create
    email = params[:email_address].to_s.strip.downcase
    user = User.find_by(email_address: email)

    if user&.active_for_authentication?
      link = MagicLink.create_for!(user, purpose: "sign_in")
      TransactionalEmail.magic_link(user, link).deliver_now
    end

    redirect_to new_public_session_path, notice: "If that account can sign in, we sent a link."
  end

  def magic_link
    @token = params[:token].to_s
    if request.post?
      consume_magic_link!
    else
      redirect_to(new_public_session_path, alert: friendly_invalid_token_message) unless MagicLink.confirmable?(@token, purpose: "sign_in")
    end
  end

  def resend_expired_magic_link
    redirect_to new_public_session_path, notice: "If that account can sign in, we sent a link."
  end

  def destroy
    terminate_session
    redirect_to root_path, status: :see_other
  end

  private

    def friendly_invalid_token_message
      "That sign in link is invalid or expired. Please request a new one."
    end

    def consume_magic_link!
      magic_link = MagicLink.consume!(@token, purpose: "sign_in")
      start_new_session_for(magic_link.user)
      redirect_to root_path, status: :see_other
    rescue MagicLink::InvalidToken, ActiveRecord::RecordNotFound
      redirect_to new_public_session_path, alert: friendly_invalid_token_message
    end
end
