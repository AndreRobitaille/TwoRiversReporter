class AddLiveActionBudgetPolicy < ActiveRecord::Migration[8.1]
  def change
    add_column :council_ai_budget_months, :live_actions, :jsonb, null: false, default: {}
    add_reference :council_ai_budget_runs, :live_budget_month, foreign_key: { to_table: :council_ai_budget_months }

    reversible do |direction|
      direction.down do
        if select_value("SELECT EXISTS (SELECT 1 FROM council_ai_budget_months WHERE live_actions <> '{}'::jsonb)")
          raise ActiveRecord::IrreversibleMigration, "Retained live spending authorization must not be discarded"
        end
      end
    end
  end
end
