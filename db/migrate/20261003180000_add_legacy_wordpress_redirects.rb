class AddLegacyWordpressRedirects < ActiveRecord::Migration[8.1]
  # High-impression WordPress paths. Trailing slashes and fragments are
  # normalized by Redirect, so one row covers each path. The 2024 tax PDF
  # is intentionally absent. find_or_create leaves an admin edit in place.
  PATHS = {
    "/two-rivers-committees" => "/committees",
    "/city-info" => "/committees",
    "/two-rivers-civic-watch" => "/",
    "/airbnb-in-two-rivers" => "/topics/230",
    "/contact" => "/about",
    "/weekly-recap-jan-12-2025" => "/meetings",
    "/city-council-meeting-apr-7-2025" => "/committees/city-council"
  }.freeze

  def up
    PATHS.each do |source_path, destination|
      Redirect.find_or_create_by!(source_path: source_path) do |redirect|
        redirect.destination = destination
        redirect.status_code = 301
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Redirects may predate this migration or have administrator edits; remove reviewed rows explicitly instead"
  end
end
