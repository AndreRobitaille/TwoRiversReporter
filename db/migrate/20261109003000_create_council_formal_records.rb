class CreateCouncilFormalRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :council_formal_sources do |t|
      t.string :title, null: false
      t.string :case_reference, null: false
      t.string :reviewing_body, null: false
      t.string :policy_label
      t.string :source_url, null: false
      t.string :record_kind, null: false
      t.date :published_on, null: false
      t.text :permitted_text, null: false
      t.jsonb :subject_names, null: false, default: []
      t.jsonb :service_period_keys, null: false, default: []
      t.text :private_notes
      t.boolean :active, null: false, default: true
      t.references :verified_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :verified_at
      t.timestamps
    end
    add_index :council_formal_sources, :source_url, unique: true

    create_table :council_formal_reviews do |t|
      t.references :council_formal_source, null: false, foreign_key: true
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
    add_index :council_formal_reviews, :input_key, unique: true

    create_table :council_formal_requests do |t|
      t.references :council_formal_review, null: false, foreign_key: true
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
    add_index :council_formal_requests, [ :council_formal_review_id, :attempt ], unique: true
  end
end
