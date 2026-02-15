class CreateTopicReviewEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :topic_review_events do |t|
      t.references :topic, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :action, null: false
      t.text :reason

      t.timestamps
    end

    add_index :topic_review_events, :created_at
    add_index :topic_review_events, [ :topic_id, :created_at ]
  end
end
