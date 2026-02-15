class CreateTopicSummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :topic_summaries do |t|
      t.references :topic, null: false, foreign_key: true
      t.references :meeting, null: false, foreign_key: true
      t.text :content, null: false
      t.string :summary_type, null: false, default: "topic_digest"
      t.jsonb :generation_data, default: {}

      t.timestamps
    end

    add_index :topic_summaries, [ :topic_id, :meeting_id, :summary_type ], unique: true
  end
end
