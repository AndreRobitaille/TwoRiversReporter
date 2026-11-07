class CreateMeetingDocumentVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :meeting_document_versions do |t|
      t.references :meeting_document, foreign_key: { on_delete: :nullify }
      t.bigint :original_document_id, null: false
      t.string :version_key, null: false
      t.string :sha256, null: false
      t.text :source_url, null: false
      t.string :document_type, null: false
      t.bigint :original_meeting_id, null: false
      t.datetime :meeting_starts_at
      t.datetime :retrieved_at, null: false
      t.datetime :source_last_modified
      t.datetime :published_at
      t.string :evidence_status, null: false, default: "collected"
      t.string :capture_method, null: false, default: "download_sha256_v1"
      t.timestamps
    end

    add_index :meeting_document_versions, :version_key, unique: true
  end
end
