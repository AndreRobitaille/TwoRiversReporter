class ApplicationsController < ApplicationController
  include Authentication

  allow_unauthenticated_access only: %i[new create edit update]

  def new
    @membership_application = MembershipApplication.new
  end

  def create
    email = params[:email_address].to_s.strip.downcase
    return redirect_to(new_application_path, notice: "Check your email for the application link.") if email.blank?

    user = User.find_or_initialize_by(email_address: email)
    return redirect_to(new_application_path, notice: "Check your email for the application link.") unless user.new_record? || user.status == "pending"

    ensure_pending_disabled_account!(user)

    membership_application = user.membership_applications.find_or_create_by!(status: "email_pending")
    magic_link = MagicLink.create_for!(user, purpose: "application")

    TransactionalEmail.application_link(user, membership_application, magic_link).deliver_now

    redirect_to new_application_path, notice: "Check your email for the application link."
  rescue LoopsDelivery::DeliveryError
    redirect_to new_application_path, notice: "Check your email for the application link."
  end

  def edit
    @membership_application = MembershipApplication.find(params[:id])
    @token = params[:token].to_s

    redirect_to new_application_path, alert: invalid_application_link_message unless application_token_matches_current_application?
  end

  def update
    @membership_application = MembershipApplication.find(params[:id])
    @token = params[:token].to_s

    unless application_token_matches_current_application?
      return redirect_to(new_application_path, alert: invalid_application_link_message)
    end

    saved = false

    ApplicationRecord.transaction do
      raise ActiveRecord::Rollback unless application_token_matches_current_application?

      MagicLink.consume!(@token, purpose: "application")
      saved = @membership_application.update(
        membership_application_params.merge(status: "submitted", submitted_at: Time.current)
      )
      raise ActiveRecord::Rollback unless saved
    end

    if saved
      AdminApplicationNotificationJob.perform_later(@membership_application.id)
      redirect_to root_path, status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def ensure_pending_disabled_account!(user)
    password = SecureRandom.urlsafe_base64(32)

    user.password = password if user.new_record? || user.password_digest.blank?
    user.password_confirmation = password if user.new_record? || user.password_digest.blank?
    user.status = "pending"
    user.disabled_at = Time.current
    user.save!
  end

  def membership_application_params
    params.require(:membership_application).permit(:first_name, :last_name, :street, :city, :state, :facebook_profile_url, :application_notes)
  end

  def application_token_matches_current_application?
    return false unless MagicLink.confirmable?(@token, purpose: "application")

    MagicLink.for_token(@token).where(purpose: "application", user_id: @membership_application.user_id).usable.exists?
  end

  def invalid_application_link_message
    "That application link is invalid or expired. Please request a new one."
  end
end
