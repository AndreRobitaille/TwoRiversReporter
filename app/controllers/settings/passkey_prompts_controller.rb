module Settings
  class PasskeyPromptsController < ApplicationController
    def destroy
      current_user.dismiss_passkey_prompt!
      redirect_back fallback_location: root_path, notice: "We'll remind you about passkeys later."
    end
  end
end
