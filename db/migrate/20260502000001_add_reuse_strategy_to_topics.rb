class AddReuseStrategyToTopics < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:topics, :reuse_strategy)
      add_column :topics, :reuse_strategy, :string, null: false, default: "canonical"
    end

    add_index :topics, :reuse_strategy unless index_exists?(:topics, :reuse_strategy)
  end
end
