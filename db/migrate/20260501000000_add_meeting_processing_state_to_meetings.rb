class AddMeetingProcessingStateToMeetings < ActiveRecord::Migration[8.1]
  def change
    add_column :meetings, :meeting_page_parsed_at, :datetime
    add_column :meetings, :processing_state, :jsonb, default: {}
  end
end
