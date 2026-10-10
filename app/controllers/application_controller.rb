class ApplicationController < ActionController::Base
  include Pagy::Method
  include Authentication
  include SiteAccess

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from ActiveRecord::RecordNotFound, with: :render_missing_record

  private

  # Public misses are real 404s. Admin keeps the flash redirect it already
  # used, because those screens are behind a session and a static 404 would
  # drop the operator out of the admin shell.
  def render_missing_record
    if request.path.start_with?("/admin")
      redirect_to root_path, alert: "That record could not be found."
    elsif request.format.html?
      render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    else
      head :not_found
    end
  end
end
