module Minutes
  class Pipeline
    class InvalidOutput < StandardError; end

    def self.needed?(meeting, kind)
      input = Input.new(meeting)
      return true if Publish.repair_needed?(meeting, input: input)
      stage = MinutesExtraction.find_by(input_key: input.key(kind))
      return stage.retryable? if stage && stage.status != "completed"
      if stage || input.completed_stage(kind)
        return Publish.repair_needed?(meeting, input: input)
      end
      # Do not turn deployment into a paid reprocessing of untouched legacy rows.
      terminal_legacy = meeting.processing_state[Publish::STATUS_KEYS.fetch(kind)].in?(%w[processed empty])
      input.text_version.present? || meeting.minutes_extractions.exists? || !terminal_legacy
    rescue Input::Unavailable
      false
    end

    def initialize(meeting_id, kind, refresh: false, budget_required: false, budget_run_id: nil)
      @meeting = Meeting.find(meeting_id)
      @kind = kind
      @refresh = refresh
      @budget_required = budget_required
      @budget_run_id = budget_run_id
    end

    def call
      if @budget_required
        @meeting.with_lock do
          attributes = { council_ai_budget_required: true }
          attributes[:council_ai_budget_run_id] = CouncilAiBudgetRun.find(@budget_run_id).id if @budget_run_id
          @meeting.update_columns(attributes)
        end
      end
      return if !@refresh && Publish.call(@meeting)
      @meeting.with_lock do
        @input = Input.new(@meeting)
        @stage = MinutesExtraction.find_by(input_key: @input.key(@kind))
        @stage ||= @input.completed_stage(@kind) unless @refresh
        @stage ||= MinutesExtraction.create!(@input.stage_attributes(@meeting, @kind))
      end
      if @stage.status == "completed"
        Publish.call(@meeting)
        return
      end
      if @input.text.length > Ai::OpenAiService::MAX_MINUTES_CHARS
        @stage.update!(status: "oversized", error_code: "input_too_large")
        stamp("needs_review")
        return
      end
      # Selection and claims serialize on the meeting. Reload its requirement
      # here so an ordinary delivery cannot claim from an earlier snapshot.
      claimed = @meeting.with_lock do
        @stage.claim!(budget_required: @meeting.council_ai_budget_required?, budget_run_id: @meeting.council_ai_budget_run_id)
      end
      return unless claimed

      begin
        service = Ai::OpenAiService.new
        recorder = RequestRecorder.new(@stage)
        response = if @kind == "votes"
          service.extract_votes(@input.text, agenda_items_text: @input.agenda_text, source: @meeting, template: @input.template(@kind), request_recorder: recorder)
        else
          service.extract_committee_members(@input.text, source: @meeting, template: @input.template(@kind), request_recorder: recorder)
        end
      rescue CouncilProfiles::ReserveAiSpend::Paused => e
        @stage.with_lock do
          @stage.update!(status: "budget_paused", attempts: @stage.attempts - 1, error_code: e.message)
        end
        stamp("budget_paused")
        return
      rescue Ai::OpenAiService::IncompleteResponseError => e
        @stage.update!(status: "incomplete", error_code: e.finish_reason || "missing_finish_reason")
        stamp("needs_review")
        return
      rescue StandardError => e
        # A transport failure may already have been billed. Do not auto-redrive
        # uncertain requests; #238 supplies the durable spend/recovery contract.
        @stage.update!(status: "uncertain", error_code: e.class.name)
        stamp("needs_review")
        return
      end

      begin
        raise InvalidOutput unless response.is_a?(String)
        data = JSON.parse(response)
        validate_output!(data)
      rescue JSON::ParserError, InvalidOutput => e
        @stage.update!(status: "failed", data: data, error_code: e.class.name)
        stamp("parse_error")
        return
      end
      locations = LocateEvidence.new(@stage).call(data) if @kind == "votes"
      @stage.update!(data: data, evidence_locations: locations, status: "completed", completed_at: Time.current)
      stamp("staged")
      Publish.call(@meeting)
    rescue Input::Unavailable
      stamp("missing_source")
      Topics::UpdateContinuityJob.perform_later(meeting_id: @meeting.id) if @kind == "votes"
    end

    private

    def stamp(status)
      @meeting.with_lock do
        if @input
          current = Input.new(@meeting)
          return unless current.key(@kind) == @input.key(@kind)
        end
        # A counterpart can publish our completed output before this marker is
        # written. Preserve that publication's terminal status for nightly repair.
        return if status == "staged" && @meeting.minutes_publication&.public_send("#{@kind}_extraction_id") == @stage.id
        @meeting.update_columns(processing_state: @meeting.processing_state.merge(
          Publish::MARKERS.fetch(@kind) => true, Publish::STATUS_KEYS.fetch(@kind) => status
        ))
      end
    rescue Input::Unavailable
      nil
    end

    def validate_output!(data)
      raise InvalidOutput unless data.is_a?(Hash)
      if @kind == "votes"
        raise InvalidOutput unless data["motions"].is_a?(Array)
        data["motions"].each do |motion|
          raise InvalidOutput unless motion.is_a?(Hash) && motion["description"].is_a?(String) && motion["description"].present?
          raise InvalidOutput unless motion["votes"].nil? || motion["votes"].is_a?(Array)
          Array(motion["votes"]).each do |vote|
            raise InvalidOutput unless vote.is_a?(Hash) && vote["member"].is_a?(String) &&
              vote["value"].is_a?(String) && vote["value"].downcase.in?(%w[yes no abstain absent recused])
          end
        end
      else
        %w[voting_members_present voting_members_absent non_voting_staff guests].each do |key|
          raise InvalidOutput unless data[key].is_a?(Array)
          data[key].each do |entry|
            name = key.in?(%w[non_voting_staff guests]) && entry.is_a?(Hash) ? entry["name"] : entry
            raise InvalidOutput unless name.is_a?(String)
          end
        end
      end
    end
  end
end
