class AddReuseStrategyToTopics < ActiveRecord::Migration[7.1]
  def change
    add_column :topics, :reuse_strategy, :string, null: false, default: "canonical"
    add_index :topics, :reuse_strategy
  end
end
