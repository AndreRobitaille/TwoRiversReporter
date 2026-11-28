class CampaignPlatformReview < ApplicationRecord
  belongs_to :member
  belongs_to :council_ai_budget_run, optional: true

  def budget_request_key
    "campaign-platform/#{id}/#{attempts + 1}"
  end

  def start!(parameters)
    CouncilProfiles::ReserveAiSpend.with_reservation(self, parameters) do |reservation|
      with_lock do
        raise CouncilProfiles::ReserveAiSpend::Paused, "already_dispatched" unless status == "pending"

        update!(status: "running", attempts: attempts + 1)
        @reservation = reservation
      end
    end
  end

  def received!(response, duration_ms:)
    transaction do
      choice = response.fetch("choices").first
      update!(response_body: choice.dig("message", "content"), status: choice["finish_reason"] == "stop" ? "received" : "needs_review")
      @reservation.update!(finished_at: Time.current, provider_usage: Ai::OpenAiService.usage_from(response))
    end
  end

  def uncertain!(_error)
    transaction do
      update!(status: "uncertain") if status == "running"
      @reservation&.update!(finished_at: Time.current) unless @reservation&.finished_at
    end
  end
end
