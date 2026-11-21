class MatchCampaignTopicsJob < ApplicationJob
  def perform(source_id, budget_run_id: nil)
    source = CampaignSource.find_by(id: source_id)
    return unless source

    version = source.current_version
    stage = Campaigns::MatchTopics.call(version, budget_run: CouncilAiBudgetRun.find_by(id: budget_run_id))
    Campaigns::PublishTopicMatches.call(stage)
    return unless stage
    return unless stage.status == "completed" ||
      version.extraction.campaign_statements.where(status: "accepted").where("data->>'comparison_heading' IS NOT NULL").exists?

    MatchCampaignActionsJob.perform_later
    MatchCampaignIssueEvidenceJob.perform_later if CouncilIssueReview.where(status: "completed").exists? ||
      MeetingSummary.published.exists?(summary_type: CouncilProfiles::SavedRecapEvidence::SUMMARY_TYPES)
  end
end
