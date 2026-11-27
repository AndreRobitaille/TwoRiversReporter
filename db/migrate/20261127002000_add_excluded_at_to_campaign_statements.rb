class AddExcludedAtToCampaignStatements < ActiveRecord::Migration[8.1]
  def change
    add_column :campaign_statements, :excluded_at, :datetime
  end
end
