module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[show approve reject toggle_admin disable revoke_session revoke_all_sessions destroy]
    before_action :refuse_self_deletion, only: :destroy
    before_action :require_fresh_reauthentication, only: %i[create destroy toggle_admin]
    # Strict, not the tolerant admin-boundary gate. The tolerant grace (a
    # recent step-up counts even from a drifted context) exists only because
    # that gate runs on every page load — a strict check there would loop
    # forever on a rotating egress. These three are each one deliberate
    # operation, not a repeated look, so the grace bought nothing here and
    # cost real protection: without this, a cookie replayed from another
    # network within fifteen minutes of the victim's sign-in could hard-delete
    # a user account, the most irreversible action in the app.
    before_action :require_matching_context, only: %i[create destroy toggle_admin]

    def index
      @users = User.order(:email_address)
    end

    def show
      @applications = @user.membership_applications.order(created_at: :desc)
      @sessions = @user.sessions.order(last_seen_at: :desc)
    end

    def new
      @user = User.new
    end

    def create
      @user = User.new(user_params.merge(admin: true, status: "active"))

      if @user.save
        AuditEvent.record!(actor: Current.user, action: "user.create", subject: @user, label: @user.email_address, request: request)
        redirect_to user_path(@user), notice: "Admin user created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def approve
      user = nil
      application = nil
      magic_link = nil

      ApplicationRecord.transaction do
        user = User.lock.find(@user.id)
        application = user.membership_applications.lock.find_by!(status: "submitted")
        magic_link = MagicLink.create_for!(user, purpose: "sign_in")

        user.update!(status: "active", disabled_at: nil)
        application.update!(status: "approved", reviewed_at: Time.current, reviewed_by: Current.session.user)
      end

      begin
        TransactionalEmail.application_approved(user, application, magic_link).deliver_now
      rescue StandardError => e
        raise e unless user && application && magic_link

        ApplicationRecord.transaction do
          user = User.lock.find(user.id)
          application = user.membership_applications.lock.find(application.id)
          user.update!(status: "pending", disabled_at: Time.current)
          application.update!(status: "submitted", reviewed_at: nil, reviewed_by: nil)
          magic_link.destroy! if magic_link.persisted?
        end

        raise e
      end
      # Only reached once the transaction has committed and the email has
      # actually gone out; the compensation path above re-raises before
      # getting here, so a failed approval never leaves an audit row behind.
      AuditEvent.record!(actor: Current.user, action: "membership_application.approve", subject: application, label: user.email_address, request: request)
      redirect_to user_path(@user), notice: "Application approved."
    end

    def reject
      application = nil

      ApplicationRecord.transaction do
        user = User.lock.find(@user.id)
        application = user.membership_applications.lock.find_by!(status: "submitted")

        user.update!(status: "rejected")
        application.update!(status: "rejected", reviewed_at: Time.current, reviewed_by: Current.session.user, rejection_reason: params[:rejection_reason].presence)
      end

      AuditEvent.record!(actor: Current.user, action: "membership_application.reject", subject: application,
        label: @user.email_address, request: request, metadata: { reason: application.rejection_reason })
      redirect_to user_path(@user), notice: "Application rejected."
    end

    def toggle_admin
      @user.update!(admin: !@user.admin?)
      AuditEvent.record!(actor: Current.user, action: "user.toggle_admin", subject: @user, label: @user.email_address,
        request: request, metadata: { admin: @user.admin? })
      redirect_to user_path(@user), notice: "Admin role updated."
    end

    def disable
      if @user.disabled_at.present? && @user.status == "active"
        @user.update!(disabled_at: nil)
        notice = "User re-enabled."
        AuditEvent.record!(actor: Current.user, action: "user.disable", subject: @user, label: @user.email_address,
          request: request, metadata: { disabled: false })
      else
        if @user.disabled_at.present?
          notice = "User remains disabled."
        else
          @user.update!(disabled_at: Time.current)
          notice = "User disabled."
          AuditEvent.record!(actor: Current.user, action: "user.disable", subject: @user, label: @user.email_address,
            request: request, metadata: { disabled: true })
        end
      end

      redirect_to user_path(@user), notice: notice
    end

    def revoke_session
      session = @user.sessions.find(params[:session_id])
      session.destroy!
      AuditEvent.record!(actor: Current.user, action: "session.revoke", subject: session, label: @user.email_address, request: request)
      redirect_to user_path(@user), notice: "Session revoked."
    end

    def revoke_all_sessions
      count = @user.sessions.delete_all
      AuditEvent.record!(actor: Current.user, action: "session.revoke_all", subject: @user, label: @user.email_address,
        request: request, metadata: { count: count })
      redirect_to user_path(@user), notice: "All sessions revoked."
    end

    # Irreversible. Sessions, magic links, passkeys and membership applications
    # go with the account; rows that merely reference it (applications this user
    # reviewed, images they uploaded, topic review events they recorded) are
    # nullified by User's associations so the record survives the reviewer.
    def destroy
      email = @user.email_address
      # Recording before the delete is deliberate, but recording and deleting
      # also have to share one transaction for the deliberate part to mean
      # anything: AuditEvent.record! commits and returns on its own, and
      # destroy! opens a transaction of its own moments later — two
      # sequential top-level statements, not one. Left that way, a refused
      # deletion (LastAdminError from destroy!'s own, separate transaction)
      # cannot retroactively undo an insert that already committed before
      # destroy! was even called, and the audit log fills with "deleted"
      # events for accounts that were never deleted. Wrapping both in one
      # ApplicationRecord.transaction makes destroy!'s raise roll back the
      # record with it, so a refused deletion leaves no record and a
      # successful one always does.
      ApplicationRecord.transaction do
        AuditEvent.record!(actor: Current.user, action: "user.destroy", subject: @user, label: email, request: request)
        @user.destroy!
      end
      redirect_to users_path, notice: "Deleted #{email} and everything attached to it."
    rescue User::LastAdminError
      # The model owns this invariant, so it holds for the console and rake too.
      # Catching it here just turns a 500 into a sentence.
      redirect_to user_path(@user), alert: "You cannot delete the last admin account."
    end

    private

      def set_user
        @user = User.find(params[:id])
      end

      # There is one owner-admin in production. Deleting your own account from
      # inside the admin area is unrecoverable — no UI exists to create the
      # first admin back.
      def refuse_self_deletion
        return unless @user.id == Current.user&.id

        redirect_to user_path(@user), alert: "You cannot delete your own account."
      end


      def user_params
        params.require(:user).permit(:email_address)
      end
  end
end
