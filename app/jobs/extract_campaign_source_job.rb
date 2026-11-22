class ExtractCampaignSourceJob < ApplicationJob
  def perform(source_id, budget_run_id: nil)
    source = CampaignSource.find_by(id: source_id)
    return unless source

    extraction = Campaigns::ExtractSource.call(source.current_version,
      budget_run: CouncilAiBudgetRun.find_by(id: budget_run_id))
    Campaigns::PublishStatements.call(extraction)
    if extraction.status == "completed" && !source.current_version.topic_matching
      MatchCampaignTopicsJob.perform_later(source.id)
    end
  end
end
