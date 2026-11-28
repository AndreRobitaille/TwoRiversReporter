class ReviewCampaignPlatformsJob < ApplicationJob
  def perform(member_id = nil)
    members = Member.where(id: CampaignStatement.where(status: "accepted", excluded_at: nil).select(:member_id))
    members = members.where(id: member_id) if member_id
    members.find_each do |member|
      CampaignStatement.current_for(member).group_by { |row| row.campaign_source_version.election_on }.each_value do |records|
        review(Campaigns::PlatformSelection.new(records))
      end
    end
  end

  private

  def review(selection)
    stage = selection.current || selection.prepare
    return unless stage
    if stage.status == "pending" && (run = Campaigns::AnalysisRun.for(stage))
      stage.update!(council_ai_budget_run: run)
      Ai::OpenAiService.new(request_timeout: Ai::OpenAiService::CAMPAIGN_ANALYSIS_TIMEOUT).extract_council_evidence(
        parameters: stage.parameters.deep_symbolize_keys, request_recorder: stage)
    end
    publish(selection, stage) if stage.status == "received"
  rescue Ai::OpenAiService::IncompleteResponseError
    # The recorder retains the returned text for review.
  rescue ActiveRecord::RecordNotUnique, CouncilProfiles::ReserveAiSpend::Paused
    # Reconciliation can pick up a matching, funded request later.
  end

  def publish(selection, stage)
    selection.publish!(stage, stage.response_body)
  rescue JSON::ParserError, ArgumentError, KeyError
    stage.with_lock { stage.update!(status: "needs_review") if stage.status == "received" }
  end
end
