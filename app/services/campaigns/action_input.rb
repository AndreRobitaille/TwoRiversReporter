module Campaigns
  class ActionInput
    RULES = "campaign_actions_v1".freeze
    attr_reader :minutes, :pairs

    def self.key(evidence)
      CouncilProfiles::ReserveAiSpend.request_digest(evidence.except("key", "statement_id", "campaign_version", "motion_id"))
    end

    def initialize(meeting, candidates)
      @minutes = Minutes::Input.new(meeting)
      @pairs = candidates.map do |candidate|
        statement = candidate.fetch(:statement)
        motion = candidate.fetch(:vote).motion
        evidence = { "rules" => RULES, "source_key" => minutes.source_key,
          "statement_id" => statement.id, "campaign_version" => statement.campaign_source_version.version_key,
          "statement" => statement.data.slice("question", "kind", "summary", "supporting_quote", "conditions", "timeframe"),
          "motion_id" => motion.id, "motion" => motion.description, "agenda" => motion.agenda_item&.display_context_title }
        # Attribution and projection IDs locate the records, but are not semantic
        # inputs. Rebuilt motions still use the current member votes at display.
        evidence.merge("key" => self.class.key(evidence))
      end.sort_by { |pair| pair.fetch("key") }
    end

    def context(pairs)
      { "rules" => RULES, "source" => minutes.source_manifest, "minutes" => minutes.text, "pairs" => pairs }
    end
  end
end
