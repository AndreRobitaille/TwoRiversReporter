module Minutes
  # Runs inside Publish's meeting/source transaction. Identity correspondence is
  # separate from semantic validation; every observation remains extracted.
  class DecisionLedger
    RULE_VERSION = "decision_identity_v1"

    def initialize(meeting, stage)
      raise ArgumentError, "Wrong meeting extraction" unless stage.original_meeting_id == meeting.id && stage.kind == "votes" && stage.status == "completed"
      @meeting, @stage = meeting, stage
      previous = meeting.minutes_publication&.votes_extraction
      raise ArgumentError, "Wrong prior publication" if previous && previous.original_meeting_id != meeting.id
      @initial = previous&.id == stage.id || !meeting.council_decisions.exists?
      @previous = previous ? previous.council_decision_observations.to_a : []
      # Rechecking locations is deterministic, including for a cached stage that
      # predates persisted checks. No provider call or old approval is required.
      @checks = LocateEvidence.new(stage).call(stage.data)
      @excerpt_counts = @checks.fetch("motions").select { |check| check["status"] == "located" }.group_by { |check| check["excerpt"] }.transform_values(&:size)
      @reordered_excerpts = reordered_excerpts(previous)
    end

    def observe(data, sequence)
      existing = @stage.council_decision_observations.find_by(sequence: sequence)
      return existing if existing

      check = @checks.fetch("motions").fetch(sequence - 1).merge(@checks.slice("rule_version", "source_key", "text_version_id"))
      context = agenda_context(data["agenda_item_ref"])
      candidates = @previous.select do |observation|
        observation.council_decision_id && (observation.location_check["excerpt"] == check["excerpt"] ||
          (observation.sequence == sequence && observation.agenda_context == context))
      end
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
      status = "unresolved"
      unless reason
        matches = candidates.select do |observation|
          observation.sequence == sequence && observation.agenda_context == context && observation.location_check["excerpt"] == check["excerpt"]
        end
        if @initial
          decision = CouncilDecision.create!(meeting: @meeting, original_meeting_id: @meeting.id)
          status = "introduced"
        elsif matches.one?
          decision = matches.first.council_decision
          status = "matched"
        else
          reason = candidates.any? ? "identity_changed" : "unmatched_revision"
        end
      end

      @stage.council_decision_observations.create!(sequence: sequence, data: data, location_check: check,
        agenda_context: context || {}, council_decision: decision, identity_status: status, reason: reason,
        candidate_decision_ids: candidates.map(&:council_decision_id).uniq.sort, rule_version: RULE_VERSION)
    end

    private

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
