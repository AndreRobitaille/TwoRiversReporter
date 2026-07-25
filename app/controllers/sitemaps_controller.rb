class SitemapsController < ApplicationController
  allow_unauthenticated_access only: :show

  # Renders /sitemap.xml for search engines. Cached for an hour so crawlers
  # don't hammer the database. New public resources must be added here by hand
  # — see the note in config/routes.rb.
  def show
    expires_in 1.hour, public: true

    @topics     = []
    @meetings   = []
    @members    = []
    @committees = []

    respond_to do |format|
      format.xml
    end
  end
end
