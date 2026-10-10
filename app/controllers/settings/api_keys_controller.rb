module Settings
  class ApiKeysController < ApplicationController
    include Reauthentication

    EXPIRY_OPTIONS = { "30" => 30.days, "90" => 90.days, "180" => 180.days }.freeze

    before_action :require_fresh_reauthentication, only: %i[new create]
    before_action :require_matching_context, only: %i[new create]
    before_action :prevent_key_caching
    rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
      redirect_to settings_api_keys_path, alert: "Too many keys created. Try again in a few minutes."
    }

    def index
      @api_keys = current_user.api_access_tokens.metadata_only.newest_first
    end

    def new
      @api_key = current_user.api_access_tokens.new
      @expiry_days = "90"
    end

    def create
      @expiry_days = key_params[:expires_in_days]
      @api_key = current_user.api_access_tokens.new(name: key_params[:name])
      expires_in = EXPIRY_OPTIONS[@expiry_days]
      unless expires_in
        @api_key.errors.add(:expires_at, "must be 30, 90, or 180 days")
        return render :new, status: :unprocessable_entity
      end

      @api_key, @plaintext_key = ApiAccessToken.issue!(user: current_user,
        name: key_params[:name], expires_in: expires_in, request: request)
      render :created, status: :created
    rescue ActiveRecord::RecordInvalid => error
      @api_key = error.record
      render :new, status: :unprocessable_entity
    end

    def destroy
      current_user.api_access_tokens.find(params[:id]).revoke!(actor: current_user, request: request)
      redirect_to settings_api_keys_path, notice: "API key revoked.", status: :see_other
    end

    def revoke_all
      current_user.with_lock do
        current_user.api_access_tokens.where(revoked_at: nil).find_each do |key|
          key.revoke!(actor: current_user, request: request)
        end
      end
      redirect_to settings_api_keys_path, notice: "All API keys revoked.", status: :see_other
    end

    private

      def key_params
        params.require(:api_access_token).permit(:name, :expires_in_days)
      end

      def prevent_key_caching
        response.headers["Cache-Control"] = "private, no-store"
      end
  end
end
