module Settings
  class SecurityController < ApplicationController
    include Authentication

    def show
      @passkey_credentials = Current.user.passkey_credentials.order(created_at: :desc, id: :desc)
    end
  end
end
