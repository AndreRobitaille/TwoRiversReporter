class CreateKnowledgeChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_chunks do |t|
      t.references :knowledge_source, null: false, foreign_key: true
      t.integer :chunk_index
      t.text :content
      t.json :metadata

      # Using JSON storage for embeddings as fallback (pgvector unavailable)
      t.json :embedding

      t.timestamps
    end
  end
end
