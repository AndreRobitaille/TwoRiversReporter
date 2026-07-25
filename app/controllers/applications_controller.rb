class ApplicationsController < ApplicationController
  include Authentication

  allow_unauthenticated_access only: %i[new create edit update]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_application_path, alert: "Try again later." }
  before_action :throttle_application_start!, only: :create

  def new
    @membership_application = MembershipApplication.new
  end

  def create
    email = params[:email_address].to_s.strip.downcase
    return redirect_to(new_application_path, notice: "Check your email for the application link.") if email.blank?

    user = User.find_or_initialize_by(email_address: email)
    return redirect_to(new_application_path, notice: "Check your email for the application link.") unless user.new_record? || user.status == "pending"

    ensure_pending_disabled_account!(user)

    membership_application = user.membership_applications.find_by(status: "email_pending")
    if membership_application.nil?
      existing_application = user.membership_applications.order(:created_at).last
      return redirect_to(new_application_path, notice: "Check your email for the application link.") if existing_application&.status == "submitted"

      membership_application = user.membership_applications.create!(status: "email_pending")
    end

    magic_link = MagicLink.create_for!(user, purpose: "application")

    TransactionalEmail.application_link(user, membership_application, magic_link).deliver_now

    redirect_to new_application_path, notice: "Check your email for the application link."
  rescue LoopsDelivery::DeliveryError
    redirect_to new_application_path, notice: "Check your email for the application link."
  end

  def edit
    @membership_application = MembershipApplication.find_by(id: params[:id])
    @token = params[:token].to_s

    return redirect_to(new_application_path, alert: invalid_application_link_message) if @membership_application.nil?

    redirect_to new_application_path, alert: invalid_application_link_message unless editable_application_token_matches_current_application?
  end

  def update
    @membership_application = MembershipApplication.find_by(id: params[:id])
    @token = params[:token].to_s

    return redirect_to(new_application_path, alert: invalid_application_link_message) if @membership_application.nil?

    unless editable_application_token_matches_current_application?
      return redirect_to(new_application_path, alert: invalid_application_link_message)
    end

    saved = false

    @membership_application.with_lock do
      raise ActiveRecord::Rollback unless @membership_application.email_pending?
      raise ActiveRecord::Rollback unless application_token_matches_current_application?

      MagicLink.consume!(@token, purpose: "application")
      saved = @membership_application.update(
        membership_application_params.merge(
          status: "submitted",
          submitted_at: Time.current,
          submitted_ip: request.remote_ip
        )
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
    user.status = "pending"
    user.disabled_at = Time.current
    user.save!
  end

  # `submitted_ip` is deliberately absent: it is set from `request.remote_ip` in
  # `update`, not from anything the applicant can type into the form.
  def membership_application_params
    params.require(:membership_application).permit(:first_name, :last_name, :street, :city, :state, :phone, :facebook_profile_url, :application_notes)
  end

  def application_token_matches_current_application?
    return false unless MagicLink.confirmable?(@token, purpose: "application")

    MagicLink.for_token(@token).where(purpose: "application", user_id: @membership_application.user_id).usable.exists?
  end

  def editable_application_token_matches_current_application?
    @membership_application.email_pending? && application_token_matches_current_application?
  end

  def invalid_application_link_message
    "That application link is invalid or expired. Please request a new one."
  end

  def throttle_application_start!
    key = "applications:create:#{request.remote_ip}"
    count = Rails.cache.increment(key, 1, initial: 0, expires_in: 3.minutes) || 1

    return if count <= 10

    redirect_to new_application_path, alert: "Try again later."
  end
end
