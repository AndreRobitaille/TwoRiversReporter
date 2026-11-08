class ExtractCouncilIssueUpdatesJob < ApplicationJob
  # An explicit source selection registers it for the existing nightly recovery.
  # Recovery is bounded to selected sources; it never discovers/backfills all years.
  def perform(document_id = nil, budget_run_id: nil)
    ids = document_id || CouncilIssueReview.where.not(meeting_document_id: nil).select(:meeting_document_id)
    budget = CouncilAiBudgetRun.find_by(id: budget_run_id)
    MeetingDocument.where(id: ids).find_each do |document|
      stage = CouncilProfiles::ExtractIssueUpdates.prepare(document)
      CouncilProfiles::ExtractIssueUpdates.call(stage, budget_run: budget) if stage
    end
  end
end
