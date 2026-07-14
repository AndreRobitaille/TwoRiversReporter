module Admin
  class RedirectsController < BaseController
    before_action :set_redirect, only: %i[edit update destroy]

    def index
      @redirects = Redirect.order(:source_path)
    end

    def new
      @redirect = Redirect.new(status_code: 301)
    end

    def create
      @redirect = Redirect.new(redirect_params)

      if @redirect.save
        redirect_to admin_redirects_path, notice: "Redirect created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @redirect.update(redirect_params)
        redirect_to admin_redirects_path, notice: "Redirect updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @redirect.destroy
      redirect_to admin_redirects_path, notice: "Redirect deleted."
    end

    private

    def set_redirect
      @redirect = Redirect.find(params[:id])
    end

    def redirect_params
      params.require(:redirect).permit(:source_path, :destination, :status_code, :note)
    end
  end
end
