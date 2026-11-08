module Campaigns
  class ActionInput
    RULES = "campaign_actions_v1".freeze
    attr_reader :minutes, :pairs

    def initialize(meeting, candidates)
      @minutes = Minutes::Input.new(meeting)
      @pairs = candidates.map do |candidate|
        statement = candidate.fetch(:statement)
        motion = candidate.fetch(:vote).motion
        evidence = { "rules" => RULES, "source_key" => minutes.source_key,
          "statement_id" => statement.id, "campaign_version" => statement.campaign_source_version.version_key,
          "statement" => statement.data.slice("question", "kind", "summary", "supporting_quote", "conditions", "timeframe"),
          "motion_id" => motion.id, "motion" => motion.description, "agenda" => motion.agenda_item&.display_context_title }
        # Attribution/location stays in the receipt, but metadata-only source
        # versions and identical statements can reuse the same semantic check.
        evidence.merge("key" => CouncilProfiles::ReserveAiSpend.request_digest(evidence.except("statement_id", "campaign_version")))
      end.sort_by { |pair| pair.fetch("key") }
    end

    def context(pairs)
      { "rules" => RULES, "source" => minutes.source_manifest, "minutes" => minutes.text, "pairs" => pairs }
    end
  end
end
