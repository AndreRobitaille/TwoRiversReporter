class AddConfirmedAbsencesToCampaignSources < ActiveRecord::Migration[8.1]
  def change
    add_column :campaign_sources, :confirmed_absences, :string, array: true, default: [], null: false
  end
end
