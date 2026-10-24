module Topics
  class AutoTriageJob < ApplicationJob
    queue_as :default
    limits_concurrency key: "global-triage", duration: 10.minutes

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
        min_confidence: Topics::TriageTool::DEFAULT_MIN_CONFIDENCE,
        max_topics: 50,
        skip_unchanged: true
      )
    end
  end
end
