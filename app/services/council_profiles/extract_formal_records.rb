module CouncilProfiles
  class ExtractFormalRecords
    def self.prepare(source)
      source.with_lock do
        return unless source.eligible?
        existing = source.current_review
        return existing if existing
        attributes = { council_formal_source: source, input_key: source.input_key, context: source.context }
        begin
          attributes[:parameters] = Ai::OpenAiService.council_formal_parameters(source.context)
        rescue Ai::OpenAiService::InputTooLargeError
          attributes.merge!(status: "oversized", error_code: "formal_source_requires_bounded_extract")
        end
        CouncilFormalReview.create!(attributes)
      end
    end

    def self.call(source, budget_run: nil)
      stage = prepare(source)
      return stage unless stage
      budget_run ||= stage.council_ai_budget_run
      claimed = stage.claim!(budget_run)
      return stage unless claimed
      raise ReserveAiSpend::Paused, "missing_budget" unless budget_run
      response = Ai::OpenAiService.new.extract_council_evidence(parameters: stage.parameters.deep_symbolize_keys,
        request_recorder: RequestRecorder.new(stage))
      stage.update!(status: "completed", data: FormalRecords.new(stage.context).parse(response), completed_at: Time.current)
      stage
    rescue ReserveAiSpend::Paused => e
      stage.update!(status: "budget_paused", error_code: e.message, attempts: stage.attempts - 1)
      stage
    rescue JSON::ParserError, FormalRecords::InvalidResponse => e
      stage.update!(status: "failed", error_code: e.class.name)
      stage
    rescue Ai::OpenAiService::IncompleteResponseError
      stage.update!(status: "incomplete", error_code: "incomplete_response")
      stage
    rescue StandardError => e
      stage.update!(status: "uncertain", error_code: e.class.name) if claimed && stage.status == "running"
      raise
    end
  end
end
