class SitemapsController < ApplicationController
  allow_unauthenticated_access only: :show

  # Rebuild the catalog so new records and access-mode changes take effect immediately.
  def show
    response.headers["Cache-Control"] = "private, no-store"
    @entries = gated_for_visitor? ? [] : Sitemaps::Catalog.new.call

    respond_to do |format|
      format.xml
    end
  end
end
