class MatchCampaignIssueEvidenceJob < ApplicationJob
  def perform(review_id = nil, budget_run_id: nil)
    candidates = Campaigns::IssueEvidenceCandidates.all
    candidates.select! { |candidate| candidate.fetch(:review).id == review_id } if review_id
    budget = CouncilAiBudgetRun.find_by(id: budget_run_id)
    candidates.group_by { |candidate| candidate.fetch(:review) }.each do |review, records|
      Campaigns::IssueEvidenceInput.prepare(review, candidates: records).each do |stage|
        Campaigns::MatchActions.call(stage, budget_run: budget)
      end
    end
  end
end
