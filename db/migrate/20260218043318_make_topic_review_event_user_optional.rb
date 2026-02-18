class MakeTopicReviewEventUserOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :topic_review_events, :user_id, true
    add_column :topic_review_events, :automated, :boolean, default: false, null: false
    add_column :topic_review_events, :confidence, :float
  end
end
