class RedesignTopicsSchema < ActiveRecord::Migration[8.1]
  def change
    # Add new columns to topics
    add_column :topics, :canonical_name, :string
    add_column :topics, :slug, :string
    add_column :topics, :review_status, :string
    add_column :topics, :lifecycle_status, :string
    add_column :topics, :first_seen_at, :datetime

    add_index :topics, :canonical_name, unique: true
    add_index :topics, :slug, unique: true
    add_index :topics, :review_status
    add_index :topics, :lifecycle_status
    add_index :topics, :first_seen_at

    # Create topic_appearances table
    create_table :topic_appearances do |t|
      t.references :topic, null: false, foreign_key: true
      t.references :meeting, null: false, foreign_key: true
      t.references :agenda_item, null: true, foreign_key: true
      t.datetime :appeared_at, null: false
      t.string :body_name
      t.string :evidence_type, null: false # agenda_item, meeting_minutes, document_citation
      t.jsonb :source_ref # e.g. { page_number: 12, document_id: 123 }

      t.timestamps
    end

    add_index :topic_appearances, [ :topic_id, :appeared_at ]

    # Create topic_status_events table
    create_table :topic_status_events do |t|
      t.references :topic, null: false, foreign_key: true
      t.string :lifecycle_status, null: false
      t.datetime :occurred_at, null: false
      t.string :evidence_type, null: false # meeting, vote, resolution, etc.
      t.jsonb :source_ref
      t.text :notes

      t.timestamps
    end

    add_index :topic_status_events, [ :topic_id, :occurred_at ]
  end
end
