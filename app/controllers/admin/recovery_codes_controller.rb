module Admin
  class RecoveryCodesController < BaseController
    def show
      @codes = session.delete(:new_recovery_codes)

      unless @codes.present?
        redirect_to admin_root_path, notice: "No new recovery codes to display."
      end
    end

    def create
      session[:new_recovery_codes] = Current.user.regenerate_recovery_codes!
      redirect_to recovery_codes_path
    end
  end
end
