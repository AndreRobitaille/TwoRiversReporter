class CreateMeetings < ActiveRecord::Migration[8.1]
  def change
    create_table :meetings do |t|
      t.string :body_name
      t.string :meeting_type
      t.datetime :starts_at
      t.string :location
      t.string :detail_page_url
      t.string :status

      t.timestamps
    end
  end
end
