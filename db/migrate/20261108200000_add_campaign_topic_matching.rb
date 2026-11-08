class AddCampaignTopicMatching < ActiveRecord::Migration[8.1]
  def change
    add_column :campaign_extractions, :purpose, :string, null: false, default: "statements"
    add_column :campaign_extractions, :context, :jsonb, null: false, default: {}
    remove_index :campaign_extractions, :campaign_source_version_id, unique: true
    add_index :campaign_extractions, [ :campaign_source_version_id, :purpose ], unique: true

    create_table :campaign_statement_topics do |t|
      t.references :campaign_extraction, null: false, foreign_key: true
      t.references :campaign_statement, null: false, foreign_key: true
      t.references :topic, null: false, foreign_key: true
      t.bigint :original_topic_id, null: false
      t.timestamps
    end
    add_index :campaign_statement_topics, [ :campaign_extraction_id, :campaign_statement_id, :original_topic_id ],
      unique: true, name: "idx_campaign_statement_topics_identity"
  end
end
