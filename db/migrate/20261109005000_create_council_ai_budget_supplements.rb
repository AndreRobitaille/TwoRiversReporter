class CreateCouncilAiBudgetSupplements < ActiveRecord::Migration[8.1]
  def change
    create_table :council_ai_budget_supplements do |t|
      t.references :council_ai_budget_month, null: false, foreign_key: true
      t.references :council_ai_budget_day, null: false, foreign_key: true
      t.string :authorization_key, null: false
      t.bigint :amount_microusd, null: false
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.bigint :original_actor_id, null: false
      t.datetime :authorized_at, null: false
      t.text :authorization_basis, null: false
      t.timestamps
    end
    add_index :council_ai_budget_supplements, :authorization_key, unique: true

    reversible do |direction|
      direction.down do
        if select_value("SELECT EXISTS (SELECT 1 FROM council_ai_budget_supplements)")
          raise ActiveRecord::IrreversibleMigration, "Retained spending supplements must not be discarded"
        end
      end
    end
  end
end
