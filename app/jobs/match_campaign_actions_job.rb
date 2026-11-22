class MatchCampaignActionsJob < ApplicationJob
  def perform(meeting_id = nil, budget_run_id: nil)
    candidates = Campaigns::ActionCandidates.all
    candidates.select! { |candidate| candidate.fetch(:vote).motion.meeting_id == meeting_id } if meeting_id
    budget = CouncilAiBudgetRun.find_by(id: budget_run_id)
    candidates.group_by { |candidate| candidate.fetch(:vote).motion.meeting }.each do |meeting, records|
      Campaigns::MatchActions.prepare(meeting, candidates: records).each do |stage|
        Campaigns::MatchActions.call(stage, budget_run: budget)
      end
    end
  end
end
