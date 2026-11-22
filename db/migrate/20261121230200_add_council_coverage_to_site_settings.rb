class AddCouncilCoverageToSiteSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :site_settings, :council_coverage, :jsonb, default: {}, null: false
  end
end
