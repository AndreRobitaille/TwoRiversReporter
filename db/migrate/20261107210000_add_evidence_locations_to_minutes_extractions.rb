class AddEvidenceLocationsToMinutesExtractions < ActiveRecord::Migration[8.1]
  def change
    add_column :minutes_extractions, :evidence_locations, :jsonb
  end
end
