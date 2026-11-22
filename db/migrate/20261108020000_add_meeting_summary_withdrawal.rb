class AddMeetingSummaryWithdrawal < ActiveRecord::Migration[8.1]
  def change
    add_column :meeting_summaries, :evidence_withdrawn_at, :datetime
  end
end
