module Campaigns
  class MatchActions
    MAX_PAIRS = 20
    MAX_CONTEXT_CHARS = 100_000

    # Cache each pair, including negative results. New statements add only their
    # missing comparisons, with one copy of the minutes shared by all members.
    def self.prepare(meeting, candidates: nil)
      candidates ||= ActionCandidates.all.select { |candidate| candidate.fetch(:vote).motion.meeting_id == meeting.id }
      return [] if candidates.empty?

      meeting.with_lock do
        input = ActionInput.new(meeting, candidates)
        stages = CampaignActionReview.where(meeting: meeting).order(:id).to_a
        assigned = stages.flat_map(&:pair_keys)
        missing = input.pairs.uniq { |pair| pair.fetch("key") }.reject { |pair| assigned.include?(pair.fetch("key")) }
        missing.each_slice(MAX_PAIRS) do |pairs|
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
    rescue Minutes::Input::Unavailable
      []
    end

    def self.call(stage, budget_run: nil)
      return stage unless stage.claim!(budget_run)
      raise CouncilProfiles::ReserveAiSpend::Paused, "missing_budget" unless budget_run

      response = Ai::OpenAiService.new.extract_campaign_source(parameters: stage.parameters.deep_symbolize_keys,
        request_recorder: CouncilProfiles::RequestRecorder.new(stage))
      stage.update!(status: "completed", data: ActionMatches.new(stage.context).parse(response), completed_at: Time.current)
      stage
    rescue CouncilProfiles::ReserveAiSpend::Paused => e
      stage.update!(status: "budget_paused", error_code: e.message, attempts: stage.attempts - 1)
      stage
    rescue JSON::ParserError, ActionMatches::InvalidResponse => e
      stage.update!(status: "failed", error_code: e.class.name)
      stage
    rescue Ai::OpenAiService::IncompleteResponseError
      stage.update!(status: "incomplete", error_code: "incomplete_response")
      stage
    rescue StandardError => e
      stage.update!(status: "uncertain", error_code: e.class.name) if stage.status == "running"
      raise
    end
  end
end
