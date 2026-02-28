class CreateMeetingAttendances < ActiveRecord::Migration[8.1]
  def change
    create_table :meeting_attendances do |t|
      t.references :meeting, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.string :status, null: false
      t.string :attendee_type, null: false
      t.string :capacity

      t.timestamps
    end

    add_index :meeting_attendances, [ :meeting_id, :member_id ], unique: true
  end
end
