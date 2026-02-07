class UpdateTopicDefaultStatusToApproved < ActiveRecord::Migration[8.1]
  def up
    # Change default for future topics
    change_column_default :topics, :status, from: "proposed", to: "approved"

    # Approve all existing proposed topics
    Topic.where(status: "proposed").update_all(status: "approved")
  end

  def down
    change_column_default :topics, :status, from: "approved", to: "proposed"
    # We don't revert the data update as we can't know which were originally proposed
  end
end
