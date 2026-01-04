class CreateMeetingDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :meeting_documents do |t|
      t.references :meeting, null: false, foreign_key: true
      t.string :document_type
      t.string :source_url
      t.datetime :fetched_at
      t.string :sha256
      t.integer :page_count
      t.integer :text_chars
      t.float :avg_chars_per_page
      t.string :text_quality

      t.timestamps
    end
  end
end
