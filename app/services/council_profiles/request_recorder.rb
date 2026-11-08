module CouncilProfiles
  class RequestRecorder
    def initialize(stage)
      @stage = stage
    end

    def start!(parameters)
      if @stage.budget_required?
        CouncilProfiles::ReserveAiSpend.with_reservation(@stage, parameters) { |reservation| create_receipt!(parameters, reservation) }
      else
        create_receipt!(parameters)
      end
    end

    def received!(response, duration_ms:)
      @receipt.transaction do
        @receipt.update!(status: "received", finished_at: Time.current, duration_ms: duration_ms,
          provider_response_id: response["id"], response_model: response["model"],
          finish_reason: response.dig("choices", 0, "finish_reason"),
          response_body: response.dig("choices", 0, "message", "content"),
          usage: Ai::OpenAiService.usage_from(response))
        @receipt.council_ai_reservation&.update!(finished_at: Time.current)
      end
    end

    def uncertain!(error)
      return unless @receipt&.persisted? && @receipt.reload.status == "dispatched"

      @receipt.update!(status: "uncertain", finished_at: Time.current, error_class: error.class.name)
    end

    private

    def create_receipt!(parameters, reservation = nil)
      @stage.with_lock do
        raise "Extraction stage is not claimed" unless @stage.status == "running"
        @receipt = @stage.requests.create!(attempt: @stage.attempts, status: "dispatched",
          council_ai_reservation: reservation,
          messages: parameters.fetch(:messages), request_parameters: parameters.except(:messages), started_at: Time.current)
      end
    end
  end
end
