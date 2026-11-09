class AddParticipationNotesToMeetingAttendances < ActiveRecord::Migration[8.1]
  def change
    add_column :meeting_attendances, :participation_notes, :jsonb, null: false, default: []
  end
end
