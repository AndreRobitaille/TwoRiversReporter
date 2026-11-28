module CouncilProfiles
  # Reuse the independently valid findings from a received response. Numbered
  # references are meaningful only against the evidence of its original request.
  class TermAssessmentDraft
    attr_reader :missing, :receipt

    def initialize(summary, evidence, receipt)
      @summary, @evidence, @receipt, @cycle = summary, evidence, receipt, summary.attempted_cycle
      request = CouncilAiReservation.find_by!(request_key: "term-summary/#{summary.id}/#{summary.attempted_cycle.iso8601}")
      unless request.request_estimate.fetch("stage_key") == evidence.digest && receipt.source == summary.member &&
          receipt.prompt_template_key == "summarize_council_term" && receipt.created_at >= request.created_at
        raise ArgumentError, "The saved response belongs to different evidence"
      end
      parameters = Ai::OpenAiService.council_term_parameters(summary.member, evidence.facts, reviewed_on: receipt.created_at.to_date)
      raise ArgumentError, "The original numbered facts have changed" unless parameters.fetch(:messages).as_json == receipt.messages

      checked = PromiseFollowThrough.checked_groups(JSON.parse(receipt.response_body), evidence, summary.member)
      accepted, held = checked.partition { |_, _, finding| finding }
      @accepted = accepted.map { |_, row, _| row }
      @missing = held.map(&:first)
    end

    def parameters
      Ai::OpenAiService.council_term_parameters(@summary.member, @evidence.facts, review_groups: missing)
    end

    def review!(authorized_run:)
      raise ArgumentError, "An exact run is required" unless authorized_run
      return if missing.empty? || @summary.reload.attempted_cycle != @cycle || @summary.complete_for?(@evidence.digest)
      recorder = TermSummaryRequest.new(@summary, @cycle, @evidence, authorized_run: authorized_run, draft_id: receipt.id)
      if reservation = CouncilAiReservation.find_by(request_key: recorder.budget_request_key)
        reviewed = PromptRun.where(source: @summary.member, prompt_template_key: receipt.prompt_template_key,
          created_at: reservation.created_at..).order(:id).detect { |row| row.messages == parameters.fetch(:messages).as_json }
        publish!(JSON.parse(reviewed.response_body)) if reviewed && (!@summary.generated_at || @summary.generated_at < reviewed.created_at)
        return
      end
      service = Ai::OpenAiService.new(request_timeout: Ai::OpenAiService::CAMPAIGN_ANALYSIS_TIMEOUT)
      response = service.summarize_council_term(@summary.member, @evidence.facts, request_recorder: recorder, review_groups: missing)
      publish!(response)
    end

    def publish!(response)
      replacements = response.fetch("promises").select { |row| missing.include?(Array(row["positions"]).sort) }
      result = response.merge("promises" => @accepted + replacements)
      @summary.publish_response!(result, @evidence, @cycle)
    end
  end
end
