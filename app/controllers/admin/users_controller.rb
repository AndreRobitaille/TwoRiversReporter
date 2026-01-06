module Admin
  class UsersController < BaseController
    def index
      @users = User.where(admin: true).order(:email_address)
    end

    def new
      @user = User.new
    end

    def create
      @user = User.new(user_params.merge(admin: true))

      if @user.save
        redirect_to users_path, notice: "Admin user created. They must enroll MFA on first sign-in."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private
      def user_params
        params.require(:user).permit(:email_address, :password, :password_confirmation)
      end
  end
end
