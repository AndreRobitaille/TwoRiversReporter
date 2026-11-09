class AddRejectedPairsToCampaignActionReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :campaign_action_reviews, :rejected_pairs, :jsonb, default: {}, null: false
  end
end
