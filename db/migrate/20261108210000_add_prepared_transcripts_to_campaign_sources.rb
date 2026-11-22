class AddPreparedTranscriptsToCampaignSources < ActiveRecord::Migration[8.1]
  def change
    add_column :campaign_sources, :prepared_transcript, :jsonb, default: {}, null: false
    add_column :campaign_source_versions, :prepared_transcript, :jsonb, default: {}, null: false
  end
end
