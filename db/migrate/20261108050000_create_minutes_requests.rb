class CreateMinutesRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :minutes_requests do |t|
      t.references :minutes_extraction, null: false, foreign_key: true
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
    add_index :minutes_requests, [ :minutes_extraction_id, :attempt ], unique: true
    add_check_constraint :minutes_requests, "attempt > 0", name: "minutes_requests_positive_attempt"
    reversible do |direction|
      direction.down do
        if select_value("SELECT EXISTS (SELECT 1 FROM minutes_requests)")
          raise ActiveRecord::IrreversibleMigration, "Retained request receipts must not be discarded"
        end
      end
    end
  end
end
