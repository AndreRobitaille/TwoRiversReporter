class ReconcileCampaignSourcesJob < ApplicationJob
  def perform
    CampaignSource.find_each do |source|
      extraction = source.current_version.extraction
      if extraction&.status == "completed"
        Campaigns::PublishStatements.call(extraction)
      elsif extraction.nil? || extraction.status == "pending"
        ExtractCampaignSourceJob.perform_later(source.id)
      end
    end
  end
end
