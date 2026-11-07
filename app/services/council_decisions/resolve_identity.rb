module CouncilDecisions
  # Identity review only. Extracted facts and their validation status are unchanged.
  class ResolveIdentity
    class Conflict < StandardError; end
    class NotAuthorized < StandardError; end

    def self.call(**args)
      new(**args).call
    end

    def initialize(observation:, action:, actor:, reason:, expected_correction_id:, request_id:, decision: nil, basis_observation: nil)
      @observation, @action, @actor, @reason = observation, action, actor, reason
      @decision, @basis, @expected, @request_id = decision, basis_observation, expected_correction_id, request_id
    end

    def call
      actor = User.find_by(id: @actor&.id, admin: true, status: "active", disabled_at: nil)
      raise NotAuthorized unless actor
      meeting = @observation.minutes_extraction.meeting
      raise Conflict, "The original meeting is unavailable" unless meeting

      meeting.with_lock do
        existing = CouncilDecisionCorrection.find_by(request_id: @request_id)
        if existing
          raise Conflict, "Request ID already belongs to another review" unless existing.request_manifest == request_manifest
          return existing
        end

        input = Minutes::Input.new(meeting)
        input.document.with_lock do
          input = Minutes::Input.new(meeting)
          raise Conflict, "Review requires the current published source" unless Minutes::Publish.current?(meeting, input: input) &&
            meeting.minutes_publication.votes_extraction_id == @observation.minutes_extraction_id
          assignment = @observation.reload.identity_assignment
          raise Conflict, "The identity has changed since review began" unless assignment && assignment.correction_id == @expected
          validate_target!(meeting)
          target = @action == "introduce" ? CouncilDecision.create!(meeting: meeting, original_meeting_id: meeting.id) : @decision
          if target && CouncilDecisionAssignment.where(minutes_extraction_id: assignment.minutes_extraction_id, council_decision: target).where.not(id: assignment.id).exists?
            raise Conflict, "This decision already identifies another observation in this source"
          end

          correction = CouncilDecisionCorrection.create!(observation: @observation, basis_observation: @basis,
            before_decision: assignment.council_decision, after_decision: target, previous_correction: assignment.correction,
            actor: actor, original_actor_id: actor.id, actor_email: actor.email_address, action: @action, reason: @reason,
            request_id: @request_id, request_manifest: request_manifest, evidence_manifest: evidence_manifest(assignment))
          assignment.update!(council_decision: target, correction: correction, conflicting_correction_ids: [])
          meeting.touch
          correction
        end
      end
    rescue Minutes::Input::Unavailable
      raise Conflict, "The current source is unavailable"
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordNotFound
      raise Conflict, "The review conflicts with a concurrent change"
    end

    private

    def validate_target!(meeting)
      raise Conflict, "Unknown identity action" unless @action.in?(%w[assign introduce unassign])
      if @action == "assign"
        raise Conflict, "Review requires this meeting's decision and retained basis" unless @decision&.persisted? && @basis&.persisted? &&
          @decision.reload.original_meeting_id == meeting.id && @basis.reload.minutes_extraction.original_meeting_id == meeting.id &&
          (@basis.council_decision_id == @decision.id || @basis.identity_assignment&.council_decision_id == @decision.id)
      elsif @decision || @basis
        raise Conflict, "Only assignment accepts an existing decision and basis"
      end
      return if @action == "unassign" && @observation.identity_assignment.council_decision_id

      check = Minutes::LocateEvidence.new(@observation.minutes_extraction).call(@observation.minutes_extraction.data).fetch("motions").fetch(@observation.sequence - 1)
      raise Conflict, "Review requires a retained unique passage" unless check["status"] == "located"
    end

    def request_manifest
      { "observation_id" => @observation.id, "action" => @action, "decision_id" => @decision&.id,
        "basis_observation_id" => @basis&.id, "actor_id" => @actor&.id, "reason" => @reason,
        "expected_correction_id" => @expected }
    end

    def evidence_manifest(assignment)
      { "review_scope" => "decision_identity_only", "source_key" => @observation.minutes_extraction.source_key,
        "text_version_id" => @observation.minutes_extraction.meeting_document_text_version_id,
        "data" => @observation.data.deep_dup, "location_check" => @observation.location_check.deep_dup,
        "resolved_conflict_ids" => assignment.conflicting_correction_ids,
        "basis_observation_id" => @basis&.id, "basis_source_key" => @basis&.minutes_extraction&.source_key }
    end
  end
end
