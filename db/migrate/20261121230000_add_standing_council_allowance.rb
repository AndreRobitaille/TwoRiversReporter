class AddStandingCouncilAllowance < ActiveRecord::Migration[8.1]
  def change
    add_column :council_ai_budget_months, :auto_renew, :boolean, default: false, null: false
  end
end
