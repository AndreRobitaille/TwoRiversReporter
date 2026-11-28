class CreateCampaignPlatformReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :campaign_platform_reviews do |t|
      t.references :member, null: false, foreign_key: true
      t.date :election_on, null: false
      t.string :input_key, null: false, index: { unique: true }
      t.jsonb :parameters, null: false
      t.jsonb :groups
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.text :response_body
      t.references :council_ai_budget_run, foreign_key: true
      t.timestamps
    end
  end
end
