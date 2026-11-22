class ExtractCouncilIssueUpdatesJob < ApplicationJob
  # Existing selections recover alongside explicitly authorized future channels.
  # No live source policy means no automatic channel discovery or paid admission.
  def perform(document_id = nil, budget_run_id: nil, meeting_id: nil)
    ids = if document_id
      [ document_id ]
    else
      selected = CouncilIssueReview.where.not(meeting_document_id: nil).pluck(:meeting_document_id)
      selected | CouncilProfiles::LiveSources.documents.pluck(:id)
    end
    budget = CouncilAiBudgetRun.find_by(id: budget_run_id)
    documents = MeetingDocument.where(id: ids)
    documents = documents.where(meeting_id: meeting_id) if meeting_id
    documents.find_each do |document|
      stage = CouncilProfiles::ExtractIssueUpdates.prepare(document)
      CouncilProfiles::ExtractIssueUpdates.call(stage, budget_run: budget) if stage
    end
  end
end
