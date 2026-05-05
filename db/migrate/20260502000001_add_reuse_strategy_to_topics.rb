class AddReuseStrategyToTopics < ActiveRecord::Migration[7.1]
  def up
    add_column :topics, :reuse_strategy, :string, null: false, default: "canonical"
    add_index :topics, :reuse_strategy
  end

  def down
    remove_index :topics, :reuse_strategy
    remove_column :topics, :reuse_strategy
  end
end
