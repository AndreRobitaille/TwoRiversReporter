class ExtractCampaignSourceJob < ApplicationJob
  def perform(source_id, budget_run_id: nil, version_id: nil)
    source = CampaignSource.find_by(id: source_id)
    return unless source

    version = source.current_version
    return if version_id && version.id != version_id

    extraction = Campaigns::ExtractSource.call(version,
      budget_run: CouncilAiBudgetRun.find_by(id: budget_run_id), find_authorized_run: budget_run_id.nil?)
    Campaigns::PublishStatements.call(extraction)
    if extraction.status == "completed" && source.reload.current_version.id == version.id
      extraction.campaign_statements.where(status: "accepted", excluded_at: nil).distinct.pluck(:member_id).each do |id|
        ReviewCampaignPlatformsJob.perform_later(id)
      end
      MatchCampaignTopicsJob.perform_later(source.id) unless version.topic_matching
    end
  end
end
