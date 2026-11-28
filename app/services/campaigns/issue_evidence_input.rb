module Campaigns
  class IssueEvidenceInput
    include ComparisonPairs

    RULES = "campaign_issue_evidence_v1".freeze

    def initialize(review, candidates)
      @review = review
      build_pairs(candidates) do |candidate|
        statement = candidate.fetch(:statement)
        evidence = candidate.fetch(:evidence)
        { "rules" => RULES, "source_key" => review.input_key,
          "statement_id" => statement.id, "campaign_version" => statement.campaign_source_version.version_key,
          "statement" => statement.data.slice("question", "kind", "summary", "supporting_quote", "conditions", "timeframe"),
          "evidence_kind" => candidate.fetch(:kind), "evidence" => evidence.except("agenda_item_id", "topic_ids"), "platform_test" => candidate[:platform_test] }.compact
      end
    end

    def context(pairs)
      reference = @review.is_a?(CouncilProfiles::SavedMeetingEvidence) ? @review.reference : { "issue_review_id" => @review.id }
      reference.merge("rules" => RULES, "assesses_city_outcomes" => true, "source" => @review.context.fetch("source"),
        "reported_on" => @review.context.fetch("reported_on"), "pairs" => pairs)
    end

    # Older direct comparisons established relevance, without assessing whether
    # the city had delivered anything. Preserve those links until rechecked.
    def pairs_for_review(stages)
      legacy = stages.select { |s| s.status == "completed" && s.issue_evidence? && !s.context["assesses_city_outcomes"] }
        .each_with_object({}) { |stage, results| results.merge!(stage.matches_by_key) }
      selected = super
      return selected if legacy.empty?
      selected.map do |pair|
        match = saved_match(pair, legacy)
        if pair["evidence_kind"] == "outcome" && pair.dig("platform_test", "undertaking") != "personal_action" &&
            !%w[proposed rejected deferred unresolved].include?(pair.dig("evidence", "status")) &&
            match&.fetch("status") == "direct" && !match["city_outcome"]
          revision = pair.merge("assess_city_outcome" => true)
          revision.merge("key" => ActionInput.key(revision))
        else
          pair
        end
      end
    end

    def saved_match(pair, results)
      return super unless pair["evidence_kind"] == "outcome"
      original = super
      # An editor's rejection of the original connection also removes its later assessment.
      return original if original && original["status"] != "direct"
      results[ActionInput.key(pair.merge("assess_city_outcome" => true))] || original
    end

    def self.prepare(review, candidates:)
      return [] unless review.status == "completed" && review.current_citation
      meeting = review.meeting_document.meeting
      meeting.with_lock do
        input = new(review, candidates)
        stages = CampaignActionReview.where(meeting: meeting).order(:id).to_a
        selected = input.pairs_for_review(stages)
        assigned = stages.flat_map(&:pair_keys).to_set
        missing = selected.reject { |pair| assigned.include?(pair.fetch("key")) }
        missing.each_slice(MatchActions::MAX_PAIRS) do |pairs|
          context = input.context(pairs)
          attributes = { meeting: meeting, context: context,
            input_key: CouncilProfiles::ReserveAiSpend.request_digest(pairs: pairs.map { |pair| pair.fetch("key") }) }
          begin
            attributes[:parameters] = Ai::OpenAiService.campaign_action_matching_parameters(context)
          rescue Ai::OpenAiService::InputTooLargeError
            attributes.merge!(status: "oversized", error_code: "action_matching_requires_partition")
          end
          stages << CampaignActionReview.create!(attributes)
        end
        keys = selected.map { |pair| pair.fetch("key") }
        stages.select { |stage| (stage.pair_keys & keys).any? }
      end
    end
  end
end
