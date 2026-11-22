class CreateCampaignSources < ActiveRecord::Migration[8.1]
  def change
    create_table :campaign_sources do |t|
      source_fields(t)
      t.timestamps
    end
    add_index :campaign_sources, :source_url, unique: true

    create_table :campaign_source_versions do |t|
      t.references :campaign_source, null: false, foreign_key: true
      source_fields(t)
      t.string :version_key, null: false
      t.string :content_sha256, null: false
      t.references :submitted_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :campaign_source_versions, :version_key, unique: true
  end

  private

  def source_fields(table)
    table.string :title, null: false
    table.string :source_url, null: false
    table.string :publisher, null: false
    table.date :published_on
    table.date :election_on, null: false
    table.string :coverage, null: false, default: "full_article"
    table.text :coverage_notes
    table.text :body, null: false
  end
end
