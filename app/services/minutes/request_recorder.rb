module Minutes
  class RequestRecorder
    def initialize(stage)
      @stage = stage
    end

    def start!(parameters)
      @stage.with_lock do
        raise "Minutes stage is not claimed" unless @stage.status == "running"
        @receipt = @stage.requests.create!(attempt: @stage.attempts, status: "dispatched",
          messages: parameters.fetch(:messages), request_parameters: parameters.except(:messages), started_at: Time.current)
      end
    end

    def received!(response, duration_ms:)
      @receipt.update!(status: "received", finished_at: Time.current, duration_ms: duration_ms,
        provider_response_id: response["id"], response_model: response["model"],
        finish_reason: response.dig("choices", 0, "finish_reason"),
        response_body: response.dig("choices", 0, "message", "content"),
        usage: Ai::OpenAiService.usage_from(response))
    end

    def uncertain!(error)
      return unless @receipt&.persisted? && @receipt.reload.status == "dispatched"

      @receipt.update!(status: "uncertain", finished_at: Time.current, error_class: error.class.name)
    end
  end
end
