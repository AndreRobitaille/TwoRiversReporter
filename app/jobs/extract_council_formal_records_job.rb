class ExtractCouncilFormalRecordsJob < ApplicationJob
  def perform(source_id = nil, budget_run_id: nil)
    sources = source_id ? CouncilFormalSource.where(id: source_id) : CouncilFormalSource.where(active: true).where.not(verified_at: nil)
    sources.find_each do |source|
      CouncilProfiles::ExtractFormalRecords.call(source, budget_run: CouncilAiBudgetRun.find_by(id: budget_run_id))
    end
  end
end
