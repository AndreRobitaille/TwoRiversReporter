class AddKnowledgeDocumentEvidence < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_sources, :source_catalog, :jsonb
    add_index :knowledge_sources, :source_catalog, using: :gin
  end
end
