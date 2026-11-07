class CreateMeetingDocumentTextVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :meeting_document_text_versions do |t|
      t.references :meeting_document_version, null: false, foreign_key: true
      t.string :fingerprint, null: false
      t.string :extractor_version, null: false
      t.string :evidence_status, null: false, default: "extracted"
      t.integer :page_count, null: false
      t.string :text_quality, null: false
      t.text :extracted_text, null: false
      t.jsonb :pages, null: false, default: []
      t.timestamps
    end
    add_index :meeting_document_text_versions, :fingerprint, unique: true
    add_reference :meeting_documents, :latest_text_version,
      foreign_key: { to_table: :meeting_document_text_versions }
  end
end
