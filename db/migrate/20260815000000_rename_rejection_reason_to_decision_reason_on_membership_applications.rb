class RenameRejectionReasonToDecisionReasonOnMembershipApplications < ActiveRecord::Migration[8.1]
  def change
    rename_column :membership_applications, :rejection_reason, :decision_reason
  end
end
