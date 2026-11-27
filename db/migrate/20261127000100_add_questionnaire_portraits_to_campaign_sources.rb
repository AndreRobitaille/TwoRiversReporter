class AddQuestionnairePortraitsToCampaignSources < ActiveRecord::Migration[8.1]
  def change
    add_column :campaign_sources, :questionnaire_portraits, :jsonb, default: {}, null: false
  end
end
