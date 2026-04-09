class AddStatedAtToKnowledgeSources < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_sources, :stated_at, :date
  end
end
