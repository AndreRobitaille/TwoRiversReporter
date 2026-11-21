module Campaigns
  class ActionInput
    include ComparisonPairs

    RULES = "campaign_actions_v1".freeze
    attr_reader :minutes

    def self.key(evidence)
      CouncilProfiles::ReserveAiSpend.request_digest(evidence.except("key", "statement_id", "campaign_version", "motion_id"))
    end

    def initialize(meeting, candidates)
      @minutes = Minutes::Input.new(meeting)
      build_pairs(candidates) do |candidate|
        statement = candidate.fetch(:statement)
        motion = candidate.fetch(:vote).motion
        { "rules" => RULES, "source_key" => minutes.source_key,
          "statement_id" => statement.id, "campaign_version" => statement.campaign_source_version.version_key,
          "statement" => statement.data.slice("question", "kind", "summary", "supporting_quote", "conditions", "timeframe"),
          "motion_id" => motion.id, "motion" => motion.description, "agenda" => motion.agenda_item&.display_context_title }
      end
    end

    def context(pairs)
      { "rules" => RULES, "source" => minutes.source_manifest, "minutes" => minutes.text, "pairs" => pairs }
    end
  end
end
