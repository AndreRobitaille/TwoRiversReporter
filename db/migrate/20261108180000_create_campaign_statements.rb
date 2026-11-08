class CreateCampaignStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :campaign_statements do |t|
      t.references :campaign_extraction, null: false, foreign_key: true
      t.references :member, foreign_key: { on_delete: :nullify }
      t.integer :sequence, null: false
      t.string :status, null: false
      t.string :exception
      t.string :validation_method, null: false
      t.datetime :validated_at, null: false
      t.jsonb :data, null: false
      t.timestamps
    end
    add_index :campaign_statements, [ :campaign_extraction_id, :sequence ], unique: true
  end
end
