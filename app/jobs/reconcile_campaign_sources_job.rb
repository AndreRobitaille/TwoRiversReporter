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
    ExtractCouncilFormalRecordsJob.perform_later if CouncilFormalSource.where(active: true).where.not(verified_at: nil).exists?
    MatchCampaignActionsJob.perform_later
    if CouncilIssueReview.where(status: "completed").exists? || MeetingSummary.published.where(summary_type: "minutes_recap").exists?
      MatchCampaignIssueEvidenceJob.perform_later
    end
    ExtractCouncilIssueUpdatesJob.perform_later if CouncilIssueReview.where.not(meeting_document_id: nil).exists? || CouncilProfiles::LiveSources.enabled?
  end
end
