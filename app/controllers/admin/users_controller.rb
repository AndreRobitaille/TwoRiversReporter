module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[show approve reject toggle_admin disable revoke_session revoke_all_sessions]

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
      @user = User.new(user_params.merge(admin: true))

      if @user.save
        redirect_to user_path(@user), notice: "Admin user created. They must enroll MFA on first sign-in."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def approve
      application = submitted_application!

      ApplicationRecord.transaction do
        @user.update!(status: "active", disabled_at: nil)
        application.update!(status: "approved", reviewed_at: Time.current, reviewed_by: Current.session.user)
      end

      magic_link = MagicLink.create_for!(@user, purpose: "sign_in")
      TransactionalEmail.application_approved(@user, application, magic_link).deliver_now
      redirect_to user_path(@user), notice: "Application approved."
    end

    def reject
      application = submitted_application!

      ApplicationRecord.transaction do
        @user.update!(status: "rejected")
        application.update!(status: "rejected", reviewed_at: Time.current, reviewed_by: Current.session.user, rejection_reason: params[:rejection_reason].presence)
      end

      redirect_to user_path(@user), notice: "Application rejected."
    end

    def toggle_admin
      @user.update!(admin: !@user.admin?)
      redirect_to user_path(@user), notice: "Admin role updated."
    end

    def disable
      if @user.disabled_at.present?
        @user.update!(disabled_at: nil)
        notice = "User re-enabled."
      else
        @user.update!(disabled_at: Time.current)
        notice = "User disabled."
      end

      redirect_to user_path(@user), notice: notice
    end

    def revoke_session
      @user.sessions.find(params[:session_id]).destroy!
      redirect_to user_path(@user), notice: "Session revoked."
    end

    def revoke_all_sessions
      @user.sessions.delete_all
      redirect_to user_path(@user), notice: "All sessions revoked."
    end

    private

      def set_user
        @user = User.find(params[:id])
      end

      def submitted_application!
        @user.membership_applications.find_by!(status: "submitted")
      end

      def user_params
        params.require(:user).permit(:email_address, :password, :password_confirmation)
      end
  end
end
