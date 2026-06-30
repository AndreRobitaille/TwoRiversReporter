class CreateTranscriptImports < ActiveRecord::Migration[8.1]
  def change
    create_table :transcript_imports do |t|
      t.references :meeting, null: false, foreign_key: true
      t.string :youtube_url, null: false
      t.string :status, null: false, default: "queued"
      t.datetime :started_at
      t.datetime :finished_at
      t.references :meeting_document, null: true, foreign_key: true
      t.json :affected_topic_ids, null: false, default: []
      t.json :step_logs, null: false, default: []
      t.string :error_class
      t.text :error_message
      t.text :error_backtrace
      t.timestamps

      t.index :status
      t.index :created_at
    end
  end
end
