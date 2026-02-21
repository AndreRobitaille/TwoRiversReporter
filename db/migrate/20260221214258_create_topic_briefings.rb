class CreateTopicBriefings < ActiveRecord::Migration[8.1]
  def change
    create_table :topic_briefings do |t|
      t.references :topic, null: false, foreign_key: true, index: { unique: true }
      t.string :headline, null: false
      t.text :editorial_content
      t.text :record_content
      t.jsonb :generation_data, null: false, default: {}
      t.string :generation_tier, null: false
      t.datetime :last_full_generation_at
      t.references :triggering_meeting, null: true, foreign_key: { to_table: :meetings }

      t.timestamps
    end
  end
end
