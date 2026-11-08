class ReconcileCampaignSourcesJob < ApplicationJob
  def perform
    CampaignSource.find_each do |source|
      extraction = source.current_version.extraction
      if extraction&.status == "completed"
        Campaigns::PublishStatements.call(extraction)
        matching = source.current_version.topic_matching
        if matching&.status == "completed"
          Campaigns::PublishTopicMatches.call(matching)
        elsif matching.nil? || matching.status == "pending"
          MatchCampaignTopicsJob.perform_later(source.id)
        end
      elsif extraction.nil? || extraction.status == "pending"
        ExtractCampaignSourceJob.perform_later(source.id)
      end
    end
    MatchCampaignActionsJob.perform_later
    ExtractCouncilIssueUpdatesJob.perform_later if CouncilIssueReview.where.not(meeting_document_id: nil).exists?
  end
end
