class EnhanceTopicsAndAddAliasesAndBlocklist < ActiveRecord::Migration[8.1]
  def change
    # Enable pg_trgm for similarity search
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    # Enhance Topics table
    change_table :topics do |t|
      t.string :status, default: "proposed", null: false
      t.boolean :pinned, default: false, null: false
      t.integer :importance, default: 0
      t.datetime :last_seen_at
      t.datetime :last_activity_at
      # name is already there and indexed
    end

    # Add GIN index for trigram similarity on topic names
    add_index :topics, :name, using: :gin, opclass: :gin_trgm_ops, name: "index_topics_on_name_trgm"

    # Create Topic Aliases
    create_table :topic_aliases do |t|
      t.references :topic, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :topic_aliases, :name, unique: true

    # Create Topic Blocklist
    create_table :topic_blocklists do |t|
      t.string :name, null: false
      t.string :reason
      t.timestamps
    end
    add_index :topic_blocklists, :name, unique: true
  end
end
