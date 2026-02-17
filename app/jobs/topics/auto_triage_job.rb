module Topics
  class AutoTriageJob < ApplicationJob
    queue_as :default

    def perform
      proposed_count = Topic.where(status: "proposed").count
      if proposed_count == 0
        Rails.logger.info "AutoTriageJob: No proposed topics to triage."
        return
      end

      Rails.logger.info "AutoTriageJob: Triaging #{proposed_count} proposed topics..."
      Topics::TriageTool.call(
        apply: true,
        dry_run: false,
        min_confidence: 0.9,
        max_topics: 50
      )
    end
  end
end
