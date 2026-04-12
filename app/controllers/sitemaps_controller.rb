class SitemapsController < ApplicationController
  # Renders /sitemap.xml for search engines. Cached for an hour so crawlers
  # don't hammer the database. New public resources must be added here by hand
  # — see the note in config/routes.rb.
  def show
    expires_in 1.hour, public: true

    @topics     = Topic.publicly_visible.order(:id)
    @meetings   = Meeting.order(:id)
    @members    = Member.order(:id)
    @committees = Committee.where(status: %w[active dormant]).order(:id)

    respond_to do |format|
      format.xml
    end
  end
end
