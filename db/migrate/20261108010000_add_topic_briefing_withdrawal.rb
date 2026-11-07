class AddTopicBriefingWithdrawal < ActiveRecord::Migration[8.1]
  def change
    add_column :topic_briefings, :evidence_withdrawn_at, :datetime
    add_reference :topic_briefings, :withdrawal_correction, foreign_key: { to_table: :council_decision_corrections }
  end
end
