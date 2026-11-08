module Campaigns
  class IssueEvidenceInput
    RULES = "campaign_issue_evidence_v1".freeze
    attr_reader :pairs

    def initialize(review, candidates)
      @review = review
      @pairs = candidates.map do |candidate|
        statement = candidate.fetch(:statement)
        evidence = candidate.fetch(:evidence)
        pair = { "rules" => RULES, "source_key" => review.input_key,
          "statement_id" => statement.id, "campaign_version" => statement.campaign_source_version.version_key,
          "statement" => statement.data.slice("question", "kind", "summary", "supporting_quote", "conditions", "timeframe"),
          "evidence_kind" => candidate.fetch(:kind), "evidence" => evidence.except("agenda_item_id", "topic_ids") }
        pair.merge("key" => ActionInput.key(pair))
      end.sort_by { |pair| pair.fetch("key") }
    end

    def context(pairs)
      { "rules" => RULES, "issue_review_id" => @review.id, "source" => @review.context.fetch("source"),
        "reported_on" => @review.context.fetch("reported_on"), "pairs" => pairs }
    end

    def self.prepare(review, candidates:)
      return [] unless review.status == "completed" && review.current_citation
      meeting = review.meeting_document.meeting
      meeting.with_lock do
        input = new(review, candidates)
        stages = CampaignActionReview.where(meeting: meeting).order(:id).to_a
        assigned = stages.flat_map(&:pair_keys)
        missing = input.pairs.uniq { |pair| pair.fetch("key") }.reject { |pair| assigned.include?(pair.fetch("key")) }
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
        keys = input.pairs.map { |pair| pair.fetch("key") }
        stages.select { |stage| (stage.pair_keys & keys).any? }
      end
    end
  end
end
