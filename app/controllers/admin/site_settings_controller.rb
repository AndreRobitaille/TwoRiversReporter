module Admin
  class SiteSettingsController < BaseController
    def show
      @site_setting = SiteSetting.instance
    end

    def update
      @site_setting = SiteSetting.instance
      current_mode = @site_setting.access_mode

      if @site_setting.update(site_setting_params)
        redirect_to admin_site_settings_path, notice: "Access mode is now #{@site_setting.access_mode}."
      else
        # #update mutates access_mode to the rejected value even though it
        # fails validation, which would leave neither radio button checked
        # on re-render. Restore the real current mode for display while
        # keeping the validation errors intact.
        @site_setting.access_mode = current_mode
        render :show, status: :unprocessable_entity
      end
    end

    private

      def site_setting_params
        params.expect(site_setting: [ :access_mode ])
      end
  end
end
