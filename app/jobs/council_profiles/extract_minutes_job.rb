module CouncilProfiles
  class ExtractMinutesJob < ApplicationJob
    queue_as :default

    def perform(meeting_id, kind, budget_run_id: nil)
      raise ArgumentError, "Unknown minutes stage" unless MinutesExtraction::KINDS.include?(kind)

      Minutes::Pipeline.new(meeting_id, kind, budget_required: true, budget_run_id: budget_run_id).call
    end
  end
end
