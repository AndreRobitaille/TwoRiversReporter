module Settings
  class ProfileController < ApplicationController
    def show
      @membership_application = current_user.membership_applications.order(created_at: :desc).first
    end
  end
end
