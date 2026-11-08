module Campaigns
  class ExtractSource
    def self.prepare(version)
      existing = CampaignExtraction.find_by(campaign_source_version: version)
      return existing if existing

      parameters = Ai::OpenAiService.campaign_request_parameters(version)
      CampaignExtraction.create!(campaign_source_version: version, input_key: CouncilProfiles::ReserveAiSpend.request_digest(
        source_version: version.version_key, parameters: parameters), parameters: parameters)
    rescue Ai::OpenAiService::InputTooLargeError
      CampaignExtraction.create!(campaign_source_version: version, input_key: version.version_key,
        status: "oversized", error_code: "source_requires_partition")
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      version.reload.extraction || raise
    end

    def self.call(version, budget_run: nil)
      stage = prepare(version)
      return stage unless stage.claim!(budget_run)
      raise CouncilProfiles::ReserveAiSpend::Paused, "missing_budget" unless budget_run

      parameters = stage.parameters.deep_symbolize_keys
      response = Ai::OpenAiService.new.extract_campaign_source(parameters: parameters,
        request_recorder: CouncilProfiles::RequestRecorder.new(stage))
      data = ExtractedStatements.new(version.body).parse(response)
      stage.update!(status: "completed", data: data, completed_at: Time.current)
      stage
    rescue CouncilProfiles::ReserveAiSpend::Paused => e
      stage.update!(status: "budget_paused", error_code: e.message, attempts: stage.attempts - 1)
      stage
    rescue JSON::ParserError, ExtractedStatements::InvalidResponse => e
      stage.update!(status: "failed", error_code: e.class.name)
      stage
    rescue Ai::OpenAiService::IncompleteResponseError
      stage.update!(status: "incomplete", error_code: "incomplete_response")
      stage
    rescue StandardError => e
      stage&.update!(status: "uncertain", error_code: e.class.name) if stage&.status == "running"
      raise
    end
  end
end
