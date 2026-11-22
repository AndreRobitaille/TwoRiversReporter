module Minutes
  # Runs inside Publish's meeting/source transaction. Identity correspondence is
  # separate from semantic validation; every observation remains extracted.
  class DecisionLedger
    RULE_VERSION = "decision_identity_v3"

    def initialize(meeting, stage)
      raise ArgumentError, "Wrong meeting extraction" unless stage.original_meeting_id == meeting.id && stage.kind == "votes" && stage.status == "completed"
      @meeting, @stage = meeting, stage
      previous = meeting.minutes_publication&.votes_extraction
      raise ArgumentError, "Wrong prior publication" if previous && previous.original_meeting_id != meeting.id
      @previous = previous ? previous.council_decision_observations.includes(identity_assignment: :correction).to_a : []
      @retained_review_ids = CouncilDecisionAssignment.joins(:minutes_extraction)
        .where(minutes_extractions: { original_meeting_id: meeting.id })
        .pluck(:correction_id, :conflicting_correction_ids).flatten.compact.uniq.sort
      @initial = previous&.id == stage.id || !meeting.council_decisions.exists?
      # Rechecking locations is deterministic, including for a cached stage that
      # predates persisted checks. No provider call or old approval is required.
      @checks = LocateEvidence.new(stage).call(stage.data)
      @excerpt_counts = @checks.fetch("motions").select { |check| check["status"] == "located" }.group_by { |check| check["excerpt"] }.transform_values(&:size)
      @reordered_excerpts = reordered_excerpts(previous)
    end

    def observe(data, sequence)
      existing = @stage.council_decision_observations.find_by(sequence: sequence)
      if existing
        existing.identity_assignment || existing.create_identity_assignment!(minutes_extraction: @stage, council_decision: existing.council_decision)
        return existing
      end

      check = @checks.fetch("motions").fetch(sequence - 1).merge(@checks.slice("rule_version", "source_key", "text_version_id"))
      context = agenda_context(data["agenda_item_ref"])
      candidates = @previous.select do |observation|
        assignment = observation.identity_assignment
        assignment && (assignment.council_decision_id || assignment.correction_id || assignment.conflicting_correction_ids.any?) && (observation.location_check["excerpt"] == check["excerpt"] ||
          (observation.sequence == sequence && observation.agenda_context == context))
      end
      unreviewed_passage = unreviewed_passage?(check)
      initial_supported = @initial && unreviewed_passage
      correction_ids = correction_ids_for(candidates)
      # Lost correspondence (including an intervening empty publication) must
      # preserve possible review dependencies without asserting an identity.
      correction_ids = @retained_review_ids if !unreviewed_passage && correction_ids.empty?
      reason = if check["status"] != "located"
        check.fetch("reason")
      elsif @excerpt_counts.fetch(check["excerpt"]) > 1
        "duplicate_excerpt_attribution"
      elsif context.nil?
        "unresolved_agenda_reference"
      elsif @reordered_excerpts.include?(check["excerpt"])
        "source_order_changed"
      end

      decision = nil
      inherited_correction = nil
      status = "unresolved"
      unless reason
        matches = candidates.select do |observation|
          observation.sequence == sequence && observation.agenda_context == context && observation.location_check["excerpt"] == check["excerpt"]
        end
        if correction_ids.any? && (!matches.one? || matches.first.identity_assignment.correction.nil?)
          reason = "identity_correction_conflict"
        elsif initial_supported && correction_ids.empty?
          decision = CouncilDecision.create!(meeting: @meeting, original_meeting_id: @meeting.id)
          status = "introduced"
        elsif matches.one?
          assignment = matches.first.identity_assignment
          correction = assignment.correction
          if correction && correction.evidence_manifest["source_key"] != @stage.source_key
            reason = "identity_correction_source_changed"
          elsif correction && correction.evidence_manifest["data"] != data
            reason = "identity_correction_conflict"
          else
            decision = assignment.council_decision
            inherited_correction = correction
            status = decision ? "matched" : "unresolved"
            reason = "identity_review_unassigned" unless decision
          end
        else
          reason = candidates.any? ? "identity_changed" : "unmatched_revision"
        end
      end

      candidate_ids = candidates.flat_map do |candidate|
        [ candidate.identity_assignment.council_decision_id, candidate.council_decision_id, *candidate.candidate_decision_ids ]
      end.compact.uniq.sort
      observation = @stage.council_decision_observations.create!(sequence: sequence, data: data, location_check: check,
        agenda_context: context || {}, council_decision: decision, identity_status: status, reason: reason,
        candidate_decision_ids: candidate_ids, rule_version: RULE_VERSION)
      conflicts = status == "unresolved" && inherited_correction.nil? ? correction_ids : []
      observation.create_identity_assignment!(minutes_extraction: @stage, council_decision: decision, correction: inherited_correction,
        conflicting_correction_ids: conflicts)
      observation
    end

    private

    def correction_ids_for(observations)
      observations.flat_map do |observation|
        assignment = observation.identity_assignment
        [ assignment.correction_id, *assignment.conflicting_correction_ids ] if assignment
      end.compact.uniq.sort
    end

    def unreviewed_passage?(check)
      return true if @retained_review_ids.empty?

      # A review must not be bypassed by treating rewritten/reordered unknown
      # evidence as a fresh baseline. Unchanged, unrelated passages can advance.
      @previous.any? do |observation|
        !review_recorded?(observation.identity_assignment) && observation.location_check["status"] == "located" &&
          observation.location_check["excerpt"] == check["excerpt"]
      end
    end

    def review_recorded?(assignment)
      assignment && (assignment.correction_id || assignment.conflicting_correction_ids.any?)
    end

    def reordered_excerpts(previous)
      changed = Set.new
      return changed unless previous

      before = passage_positions(LocateEvidence.new(previous).call(previous.data))
      after = passage_positions(@checks)
      # Compare relative retained locations, independently of provider sequence.
      # A heading/page shift is harmless; an inversion holds both participants.
      (before.keys & after.keys).combination(2) do |left, right|
        next if (before[left] <=> before[right]) == (after[left] <=> after[right])
        changed.merge([ left, right ])
      end
      changed
    end

    def passage_positions(checks)
      checks.fetch("motions").select { |check| check["status"] == "located" }.group_by { |check| check["excerpt"] }.filter_map do |excerpt, matches|
        next unless matches.one?
        [ excerpt, matches.first.fetch("locations").first.values_at("page_number", "start_char") ]
      end.to_h
    end

    def agenda_context(reference)
      return { "unassigned" => true } if reference.nil?
      return unless reference.is_a?(String) && reference.present?

      matches = Array(@stage.input_manifest["agenda"]).select do |row|
        label = row[1].present? ? "#{row[1]}: #{row[2]}" : row[2]
        label = "#{label} (#{row[4]})" if row[4].present?
        label == reference
      end
      return unless matches.one?
      row = matches.first
      { "number" => row[1], "title" => row[2], "parent_title" => row[4] }
    end
  end
end
