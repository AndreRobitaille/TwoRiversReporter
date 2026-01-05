class CreateMeetingSummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :meeting_summaries do |t|
      t.references :meeting, null: false, foreign_key: true
      t.string :summary_type
      t.text :content

      t.timestamps
    end
  end
end
