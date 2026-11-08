class MatchCampaignTopicsJob < ApplicationJob
  def perform(source_id, budget_run_id: nil)
    source = CampaignSource.find_by(id: source_id)
    return unless source

    stage = Campaigns::MatchTopics.call(source.current_version, budget_run: CouncilAiBudgetRun.find_by(id: budget_run_id))
    Campaigns::PublishTopicMatches.call(stage)
    MatchCampaignActionsJob.perform_later if stage&.status == "completed"
    MatchCampaignIssueEvidenceJob.perform_later if stage&.status == "completed" && CouncilIssueReview.where(status: "completed").exists?
  end
end
