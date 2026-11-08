class AddCouncilAiSpendReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :council_ai_budget_days do |t|
      t.date :budget_on, null: false
      t.bigint :limit_microusd, null: false
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.bigint :original_actor_id, null: false
      t.datetime :authorized_at, null: false
      t.text :authorization_basis, null: false
      t.timestamps
    end
    add_index :council_ai_budget_days, :budget_on, unique: true

    create_table :council_ai_budget_runs do |t|
      t.references :council_ai_budget_day, null: false, foreign_key: true
      t.bigint :limit_microusd, null: false
      t.bigint :request_limit_microusd, null: false
      t.integer :max_requests, null: false
      t.integer :max_concurrent, null: false
      t.integer :max_input_tokens, null: false
      t.integer :max_output_tokens, null: false
      t.datetime :expires_at, null: false
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.bigint :original_actor_id, null: false
      t.datetime :authorized_at, null: false
      t.text :authorization_basis, null: false
      t.jsonb :request_estimates, null: false
      t.datetime :revoked_at
      t.timestamps
    end

    create_table :council_ai_reservations do |t|
      t.references :council_ai_budget_run, null: false, foreign_key: true
      t.jsonb :request_estimate, null: false
      t.string :request_key, null: false
      t.bigint :reserved_microusd, null: false
      t.datetime :finished_at
      t.timestamps
    end
    add_index :council_ai_reservations, :request_key, unique: true

    add_column :minutes_extractions, :budget_required, :boolean, null: false, default: false
    add_reference :minutes_extractions, :council_ai_budget_run, foreign_key: true
    add_reference :minutes_requests, :council_ai_reservation, foreign_key: true, index: { unique: true }
    add_column :meetings, :council_ai_budget_required, :boolean, null: false, default: false
    add_reference :meetings, :council_ai_budget_run, foreign_key: true

    reversible do |direction|
      direction.down do
        if select_value("SELECT EXISTS (SELECT 1 FROM council_ai_reservations)") ||
            select_value("SELECT EXISTS (SELECT 1 FROM council_ai_budget_days)")
          raise ActiveRecord::IrreversibleMigration, "Retained spending authorization and reservations must not be discarded"
        end
      end
    end
  end
end
