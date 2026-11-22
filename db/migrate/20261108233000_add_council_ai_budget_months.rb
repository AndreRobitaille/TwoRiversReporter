class AddCouncilAiBudgetMonths < ActiveRecord::Migration[8.1]
  def change
    create_table :council_ai_budget_months do |t|
      t.date :budget_month, null: false
      t.bigint :limit_microusd, null: false
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.bigint :original_actor_id, null: false
      t.datetime :authorized_at, null: false
      t.text :authorization_basis, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :council_ai_budget_months, :budget_month, unique: true

    reversible do |direction|
      direction.down do
        if select_value("SELECT EXISTS (SELECT 1 FROM council_ai_budget_months)")
          raise ActiveRecord::IrreversibleMigration, "Retained monthly spending authorization must not be discarded"
        end
      end
    end
  end
end
