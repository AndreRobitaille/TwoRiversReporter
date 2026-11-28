module CouncilProfiles
  # An editor's exact spending approval can revisit just the held positions.
  class ReviewTermAssessmentJob < ApplicationJob
    def perform(summary_id, prompt_run_id, budget_run_id)
      summary = CouncilTermSummary.find(summary_id)
      member = summary.member
      period = ResidentContent::CouncilPeriod.new(member)
      return unless period.selected&.started_on == summary.term_started_on && !period.selected.ended_on
      evidence = TermEvidence.new(member, period: period)
      return if summary.complete_for?(evidence.digest)
      draft = TermAssessmentDraft.new(summary, evidence, PromptRun.find(prompt_run_id))
      draft.review!(authorized_run: CouncilAiBudgetRun.find(budget_run_id))
    end
  end
end
