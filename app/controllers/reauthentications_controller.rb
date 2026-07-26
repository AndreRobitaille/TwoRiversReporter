# Step-up reauthentication. Deliberately gated by neither Reauthentication
# callback: this is the page that resolves an unverified context, so gating it
# would redirect it to itself.
class ReauthenticationsController < ApplicationController
  include Authentication
  include WebauthnVerification

  rate_limit to: 10, within: 3.minutes, only: %i[magic_link],
    with: -> { redirect_to new_reauthentication_path, alert: "Try again later." }
  rate_limit to: 10, within: 3.minutes, only: %i[passkey_options passkey],
    with: -> { head :too_many_requests }

  def new
    @passkey_available = Current.user.passkey_credentials.exists?
  end

  def passkey_options
    options = WebAuthn::Credential.options_for_get(
      allow: Current.user.passkey_credentials.pluck(:external_id),
      user_verification: :required
    )

    session[:reauthentication_challenge] = options.challenge
    render json: options
  end

  def passkey
    credential = verified_get_credential(params[:credential], challenge_key: :reauthentication_challenge)
    return if performed?

    # The allow-list above only steers the browser. The credential still has to
    # be checked against this account server-side, or a valid assertion for
    # somebody else's passkey would step this session up.
    passkey = Current.user.passkey_credentials.find_by(external_id: credential.id)
    return head :unauthorized unless passkey

    passkey.update!(sign_count: credential.sign_count, last_used_at: Time.current)
    Current.session.reauthenticate!(SessionContext.from_request(request))

    render json: { success: true, redirect_to: after_authentication_url }
  end

  # The ordinary sign-in link, not a reauth-specific token. An emailed link
  # frequently opens in a different browser than the one awaiting step-up —
  # tapped from a phone while the session sits in desktop Chrome — where a
  # reauth token would have no session to apply to. Treating it as a sign-in
  # means whichever browser opens it ends up authenticated, freshly stepped up,
  # and pointed at the original destination.
  def magic_link
    link = MagicLink.create_for!(Current.user, purpose: "sign_in")
    TransactionalEmail.magic_link(Current.user, link).deliver_now

    redirect_to new_reauthentication_path, notice: "Check your email — we've sent you a link."
  rescue LoopsDelivery::DeliveryError
    redirect_to new_reauthentication_path, alert: "We couldn't send that message right now. Try again later."
  end
end
