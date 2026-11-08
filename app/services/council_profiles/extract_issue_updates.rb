module CouncilProfiles
  class ExtractIssueUpdates
    MAX_CONTEXT_CHARS = 60_000
    MAX_PACKET_CONTEXT_CHARS = 120_000

    def self.prepare(document)
      document.with_lock do
        input = IssueInput.new(document)
        # Template/model edits alone do not reopen historical sources.
        existing = CouncilIssueReview.find_by(input_key: input.key)
        return existing if existing
        # The response schema is not evidence identity: extending extraction must
        # not reopen completed historical sources or cause extra paid calls.
        context = input.context.merge("schema_version" => 3)
        attributes = { meeting_document: document, input_key: input.key, context: context }
        begin
          attributes[:parameters] = Ai::OpenAiService.council_issue_parameters(context)
        rescue Ai::OpenAiService::InputTooLargeError
          attributes.merge!(status: "oversized", error_code: "issue_source_requires_partition")
        end
        CouncilIssueReview.create!(attributes)
      end
    rescue IssueInput::Unavailable
      nil
    end

    def self.call(stage, budget_run: nil)
      # Never spend on a source that was replaced after preparation.
      return stage unless stage.meeting_document && IssueInput.new(stage.meeting_document).key == stage.input_key
      claimed = false
      budget_run ||= LiveBudget.call(stage)
      claimed = stage.claim!(budget_run)
      return stage unless claimed
      raise ReserveAiSpend::Paused, "missing_budget" unless budget_run
      response = Ai::OpenAiService.new.extract_council_evidence(parameters: stage.parameters.deep_symbolize_keys,
        request_recorder: RequestRecorder.new(stage))
      stage.update!(status: "completed", data: IssueUpdates.new(stage.context).parse(response), completed_at: Time.current)
      stage
    rescue IssueInput::Unavailable
      stage
    rescue ReserveAiSpend::Paused => e
      stage.with_lock do
        if claimed || stage.status.in?(%w[pending failed budget_paused])
          stage.update!(status: "budget_paused", error_code: e.message, attempts: stage.attempts - (claimed ? 1 : 0))
        end
      end
      stage
    rescue JSON::ParserError, IssueUpdates::InvalidResponse => e
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
