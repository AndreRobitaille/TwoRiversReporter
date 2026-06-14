class CreateGeneratedImages < ActiveRecord::Migration[8.1]
  def change
    create_table :generated_images do |t|
      t.references :imageable, polymorphic: true, null: false, index: true
      t.string :status, null: false, default: "pending"
      t.string :purpose, null: false, default: "feature_and_og"
      t.jsonb :visual_brief, null: false, default: {}
      t.text :prompt
      t.references :source_summary, foreign_key: { to_table: :meeting_summaries, on_delete: :nullify }
      t.references :source_briefing, foreign_key: { to_table: :topic_briefings, on_delete: :nullify }
      t.string :source_generation_tier
      t.string :source_content_fingerprint
      t.string :model
      t.string :requested_size
      t.string :output_format
      t.integer :retry_count, null: false, default: 0
      t.text :failure_reason
      t.datetime :generated_at
      t.boolean :admin_override, null: false, default: false
      t.text :custom_prompt
      t.references :uploaded_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :generated_images, [ :imageable_type, :imageable_id, :status, :purpose ], name: "index_generated_images_current_lookup"
    add_index :generated_images, :source_content_fingerprint
  end
end
