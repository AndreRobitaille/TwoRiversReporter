class SessionsController < ApplicationController
  include Authentication

  allow_unauthenticated_access only: %i[new create magic_link resend_expired_magic_link]
  rate_limit to: 10, within: 3.minutes, only: %i[create magic_link resend_expired_magic_link], with: -> { redirect_to new_public_session_path, alert: "Try again later." }

  def new
  end

  def create
    email = params[:email_address].to_s.strip.downcase

    # Every branch below produces the same redirect. The identical response is
    # what prevents address enumeration; the email is what gives a real person
    # a definitive answer.
    #
    # A malformed address is dropped here rather than rejected: it cannot be
    # delivered to, and telling the browser about it would make "not a real
    # address" distinguishable from "not an account" — the exact distinction
    # this action exists to hide. It is dropped *before* SignInAttempt so
    # garbage input cannot burn a real address's throttle window either.
    deliver_sign_in_response(email) if User.deliverable_address?(email) && !SignInAttempt.throttled?(email)

    redirect_to new_public_session_path, notice: "Check your email — we've sent you a message."
  rescue LoopsDelivery::DeliveryError
    # The attempt was recorded before delivery was tried. Give it back, or "try
    # again later" would be a lie for the next 15 minutes.
    SignInAttempt.release!(email)
    redirect_to new_public_session_path, alert: "We couldn't send that message right now. Try again later."
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
    redirect_to new_public_session_path, notice: "Check your email — we've sent you a message."
  end

  def destroy
    terminate_session
    redirect_to root_path, status: :see_other
  end

  private

    def deliver_sign_in_response(email)
      SignInAttempt.record!(email)
      user = User.find_by(email_address: email)

      if user&.active_for_authentication?
        link = MagicLink.create_for!(user, purpose: "sign_in")
        TransactionalEmail.magic_link(user, link).deliver_now
      elsif user&.status == "pending"
        TransactionalEmail.application_pending(user).deliver_now
      else
        TransactionalEmail.no_account(email).deliver_now
      end
    end

    def friendly_invalid_token_message
      "That sign in link is invalid or expired. Please request a new one."
    end

    def consume_magic_link!
      magic_link = MagicLink.consume!(@token, purpose: "sign_in")
      start_new_session_for(magic_link.user)
      redirect_to after_authentication_url, status: :see_other
    rescue MagicLink::InvalidToken, ActiveRecord::RecordNotFound
      redirect_to new_public_session_path, alert: friendly_invalid_token_message
    end
end
