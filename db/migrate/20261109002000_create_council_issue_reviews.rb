class CreateCouncilIssueReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :council_issue_reviews do |t|
      t.references :meeting_document, foreign_key: { on_delete: :nullify }
      t.references :council_ai_budget_run, foreign_key: true
      t.string :input_key, null: false
      t.jsonb :context, null: false, default: {}
      t.jsonb :parameters, null: false, default: {}
      t.jsonb :data, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.string :error_code
      t.datetime :completed_at
      t.timestamps
    end
    add_index :council_issue_reviews, :input_key, unique: true

    create_table :council_issue_requests do |t|
      t.references :council_issue_review, null: false, foreign_key: true
      t.references :council_ai_reservation, null: false, foreign_key: true, index: { unique: true }
      t.integer :attempt, null: false
      t.string :status, null: false
      t.jsonb :messages, null: false
      t.jsonb :request_parameters, null: false
      t.string :provider_response_id
      t.string :response_model
      t.string :finish_reason
      t.jsonb :usage
      t.text :response_body
      t.string :error_class
      t.integer :duration_ms
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.timestamps
    end
    add_index :council_issue_requests, [ :council_issue_review_id, :attempt ], unique: true
  end
end
