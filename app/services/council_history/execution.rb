module CouncilHistory
  # Set only by the synchronous operator task. The normal workers keep their
  # usual adapter, source window and independent comparison authorization.
  class Execution < ActiveSupport::CurrentAttributes
    attribute :meeting_id, :stage, :pilot, :request

    def self.chat(parameters)
      raise "Historical meeting and stage required" unless meeting_id && stage
      parameters[:max_completion_tokens] ||= 12_000
      receipt, estimate = CouncilHistoryRequest.reserve!(meeting_id: meeting_id, stage: stage, pilot: pilot, parameters: parameters)
      response = set(request: receipt) { yield }
      receipt.finish!(response, estimate)
      response
    end
  end
end
