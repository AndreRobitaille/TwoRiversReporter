class AddGenerationDataToMeetingSummaries < ActiveRecord::Migration[8.1]
  def change
    add_column :meeting_summaries, :generation_data, :jsonb, default: {}
  end
end
