class CreateMinutesFactSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :minutes_extractions do |t|
      t.references :meeting, foreign_key: { on_delete: :nullify }
      t.bigint :original_meeting_id, null: false
      t.references :meeting_document_text_version, foreign_key: true
      t.string :kind, null: false
      t.string :input_key, null: false
      t.string :source_key, null: false
      t.jsonb :input_manifest, null: false
      t.text :source_text, null: false
      t.jsonb :data
      t.string :status, default: "pending", null: false
      t.integer :attempts, default: 0, null: false
      t.string :error_code
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :minutes_extractions, :input_key, unique: true

    create_table :minutes_publications do |t|
      t.references :meeting, foreign_key: { on_delete: :nullify }
      t.bigint :original_meeting_id, null: false
      t.references :votes_extraction, null: false, foreign_key: { to_table: :minutes_extractions }
      t.references :attendance_extraction, null: false, foreign_key: { to_table: :minutes_extractions }
      t.string :fingerprint, null: false
      t.jsonb :projection_context, null: false
      t.timestamps
    end
    add_index :minutes_publications, :fingerprint, unique: true
    add_reference :meetings, :minutes_publication, foreign_key: true
    add_column :votes, :evidence_basis, :string, default: "legacy", null: false
  end
end
