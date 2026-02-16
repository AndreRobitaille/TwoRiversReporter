class CreateKnowledgeSourceTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_source_topics do |t|
      t.references :knowledge_source, null: false, foreign_key: true
      t.references :topic, null: false, foreign_key: true
      t.float :relevance_score, default: 0.0 # Heuristic score
      t.boolean :verified, default: false # For manual confirmation

      t.timestamps
    end

    add_index :knowledge_source_topics, [ :knowledge_source_id, :topic_id ], unique: true, name: 'index_ks_topics_on_source_and_topic'
  end
end
