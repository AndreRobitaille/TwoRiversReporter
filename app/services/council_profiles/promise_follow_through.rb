module CouncilProfiles
  class PromiseFollowThrough
    LABELS = {
      "city_result" => "City delivered the outcome", "city_progress" => "City made progress",
      "contrary" => "Acted against the position", "met" => "Documented result", "pursued" => "Acted, result unconfirmed", "blocked" => "Acted and was outvoted",
      "missed" => "Missed opportunity", "fell_short" => "Fell short", "unresolved" => "Open in the public record"
    }.freeze

    POINTS = {
      "met" => 1, "city_result" => 1, "city_progress" => 0.5, "contrary" => -2.5, "missed" => -0.5, "unresolved" => -0.5,
      "fell_short" => -0.5, "pursued" => 0.5, "blocked" => 0
    }.freeze

    MATERIAL_EFFECTS = %w[binding_decision committed_resources operating_program documented_result].freeze

    def self.from_response(result, evidence, member, expected: position_groups(evidence.facts))
      groups = result.fetch("promises")
      unless groups.is_a?(Array) && groups.all? { |row| row.is_a?(Hash) && row["positions"].is_a?(Array) }
        raise ArgumentError, "Invalid promise list"
      end
      groups = groups.map do |row|
        ids = row.fetch("positions").map { |ref| ref.is_a?(Hash) ? ref["id"] : ref }
        raise ArgumentError, "Invalid campaign reference" unless ids.all?(Integer)
        row.merge("positions" => ids.sort)
      end
      raise ArgumentError, "Incomplete promise coverage" unless groups.pluck("positions").sort == expected.sort
      groups.map do |group|
        status = group.fetch("status")
        positions = group.fetch("positions")
        records = group["record"]
        reason = group["reason"]
        unless LABELS.key?(status) && reason.is_a?(String) && reason.strip.length.between?(5, 360) &&
            records.is_a?(Array) && records.size <= 4 && records.all? { |id| id.is_a?(Integer) && id.between?(1, evidence.facts.size) && !evidence.facts[id - 1][:kind].end_with?(" campaign") }
          raise ArgumentError, "Invalid promise assessment"
        end
        headings = positions.map { |id| evidence.facts.fetch(id - 1).fetch(:position) }
        relevant = records.map { |id| evidence.facts.fetch(id - 1) }.select { |fact| !fact[:position] || headings.include?(fact[:position]) }
        review_id = current_review_id(evidence.facts, headings, relevant)
        if review_id
          review = evidence.facts.fetch(review_id - 1)
          status, reason, records = review.fetch(:reviewed_status), review.fetch(:text), [ review_id ]
        else
          if %w[city_result city_progress].include?(status) && positions.any? { |id| evidence.facts.fetch(id - 1)[:undertaking] == "personal_action" }
            raise ArgumentError, "The candidate promised a personal action"
          end
          validate_judgment!(group, relevant, headings, member)
          if status == "pursued" && relevant.present? && relevant.all? { |fact| outvoted?(fact, group["attribution"]) }
            status = "blocked"
          end
          if %w[city_result city_progress].include?(status)
            city = relevant.find { |fact| fact[:outcome_quote] == group["attribution"] && headings.include?(fact[:position]) && fact[:city_outcome] == (status == "city_result" ? "delivered" : "advanced") }
            reason = city.fetch(:outcome_quote)
          end
        end

        ids = positions + records
        campaign = evidence.facts.fetch(positions.first - 1)
        { "heading" => headings.uniq.join(" / "), "label" => campaign.fetch(:text), "quote" => campaign.fetch(:promise_words).first.fetch("supporting_quote"), "status" => status, "reason" => reason.strip,
          "facts" => ids.map { |id| evidence.fact_keys.fetch(id - 1) }.uniq,
          "sources" => ids.flat_map { |id| evidence.facts.fetch(id - 1).fetch(:sources) }.uniq }
      end
    end

    # Check the whole evidence inventory before accepting the generated citations.
    def self.current_review_id(facts, headings, cited)
      review = facts.select { |fact| fact[:kind] == "Public record" && fact[:reviewed_on] && LABELS.key?(fact[:reviewed_status]) && headings.include?(fact[:position]) }
        .max_by { |fact| fact.fetch(:reviewed_on).to_date }
      # A newly matched old decision can change a review, too. Check the evidence
      # inventory before choosing the saved verdict or accepting generated prose.
      latest = %i[opposed_positions advanced_positions].to_h do |direction|
        matches = facts.select { |fact| Array(fact[direction]).intersect?(headings) }
        [ direction, matches.max_by { |fact| fact.fetch(:dates).max } ]
      end
      prior_status = review&.fetch(:reviewed_status)
      prior_opposed = prior_status == "contrary"
      opposing, supporting = latest.values_at(:opposed_positions, :advanced_positions)
      if (opposing && !prior_opposed) || (supporting && (opposing || prior_opposed))
        required = [ opposing, supporting ].compact
        required << review if prior_opposed || %w[met pursued blocked].include?(prior_status)
        raise ArgumentError, "Assess the opposing and supporting actions" unless (required - cited).empty?
        return
      end
      return unless review

      newer_action = cited.any? do |fact|
        fact[:kind].start_with?("Member ") && (Array(fact[:matched_positions]) - Array(fact[:unclear_positions])).intersect?(headings) &&
          Array(fact[:dates]).any? { |date| date.to_date > review.fetch(:reviewed_on).to_date }
      end
      facts.index(review) + 1 unless newer_action
    end

    def self.validate_judgment!(group, relevant, headings, member)
      status = group.fetch("status")
      opposing = relevant.select { |fact| fact[:kind].start_with?("Member ") && Array(fact[:opposed_positions]).intersect?(headings) }
      if status == "contrary"
        return if relevant.any? { |fact| fact[:kind] == "Public record" && fact[:reviewed_on] && fact[:reviewed_status] == "contrary" && headings.include?(fact[:position]) }
        return if opposing.any? { |fact| !Array(fact[:advanced_positions]).intersect?(headings) }
        raise ArgumentError, "A deduction needs a verified opposing action on this position"
      end
      if opposing.any?
        corroborated = relevant.any? do |fact|
          Array(fact[:advanced_positions]).intersect?(headings) ||
            (fact[:kind] == "Public record" && %w[met pursued blocked].include?(fact[:reviewed_status]))
        end
        raise ArgumentError, "A different verdict needs evidence of follow-through alongside the opposing action" unless corroborated
        relevant = relevant.reject { |fact| opposing.include?(fact) || fact[:kind] == "Minutes excerpt" }
      end
      if %w[city_result city_progress].include?(status)
        effect = status == "city_result" ? "delivered" : "advanced"
        confirmed = relevant.any? do |fact|
          fact[:kind] == "City outcome on campaign position" && headings.include?(fact[:position]) &&
            fact[:city_outcome] == effect && fact[:outcome_quote].present? && group["attribution"] == fact[:outcome_quote]
        end
        raise ArgumentError, "A city outcome needs a dated, directly matched source for this undertaking" unless confirmed
        return
      end
      return if status == "unresolved"

      if %w[met pursued blocked].include?(status)
        relevant = relevant.reject do |fact|
          Array(fact[:unclear_positions]).intersect?(headings) && !Array(fact[:advanced_positions]).intersect?(headings)
        end
      end

      if status == "missed"
        return if relevant.any? { |fact| fact[:kind] == "Public record" && fact[:reviewed_status] == status && fact[:position] }
        raise ArgumentError, "A missed opportunity needs a reviewed record for this promise"
      end
      if status == "met" && !MATERIAL_EFFECTS.include?(group["material_effect"])
        raise ArgumentError, "Follow-through needs a material effect"
      end
      personal = relevant.select do |fact|
        (fact[:kind].start_with?("Member ") && Array(fact[:matched_positions]).intersect?(headings)) ||
          (fact[:kind] == "Public record" && fact[:reviewed_status] == status && fact[:position] && named_action?(fact[:text], [ member.name.split.last ])) ||
          attributed_excerpt?(fact, group["attribution"])
      end
      raise ArgumentError, "Promise judgment needs attributed work on this position" if personal.empty?
      if status == "blocked" && personal.none? { |fact| outvoted?(fact, group["attribution"]) }
        raise ArgumentError, "A blocked promise needs a recorded losing action"
      end
    end

    def self.outvoted?(fact, attribution)
      text = fact.fetch(:text)
      if fact[:kind] == "Member vote"
        return text.match?(/\AMember voted (?:yes\. Council result: (?:failed|defeated|rejected)|no\. Council result: (?:passed|approved))\b/i)
      end
      # In a longer minutes passage the member and disposition must be in the quoted action.
      text = attribution.to_s if fact[:kind] == "Minutes excerpt"
      text.match?(/\b(?:outvoted|motion (?:failed|was defeated|was rejected|did not (?:carry|pass))|voted down)\b/i)
    end

    def self.attributed_excerpt?(fact, quote)
      return false unless fact[:kind] == "Minutes excerpt" && quote.is_a?(String) && quote.length >= 12
      fact[:text].include?(quote) && named_action?(quote, fact.fetch(:identity))
    end

    def self.named_action?(text, names)
      who = Regexp.union(names)
      text.match?(/\b(?:#{who})\s+(?:moved|seconded|voted|asked|introduced|proposed|requested|supported|opposed|recommended)\b/i) ||
        text.match?(/\b(?:moved|made|seconded|supported) by (?:#{who})\b/i) ||
        text.match?(/\bVoting (?:Yea|Nay|Yes|No):\s*(?:[[:alpha:].’'-]+(?: [[:alpha:].’'-]+)?,\s*)*(?:#{who})\b/i)
    end

    def self.position_groups(facts)
      facts.each_index.select { |i| facts[i][:promise_words].present? }
        .group_by { |i| facts[i].fetch(:promise_words) }.values.map { |indexes| indexes.map(&:succ) }
    end

    # Only this local path can mark a position as awaiting review. Every scored
    # finding still goes through the full attribution and direction checks.
    def self.checked_groups(result, evidence, member)
      rows = result.fetch("promises")
      raise ArgumentError, "Invalid promise list" unless rows.is_a?(Array)
      indexed = rows.select { |row| row.is_a?(Hash) && row["positions"].is_a?(Array) }.group_by do |row|
        ids = row["positions"].map { |ref| ref.is_a?(Hash) ? ref["id"] : ref }
        ids.sort if ids.all?(Integer)
      end
      position_groups(evidence.facts).map do |group|
        candidates = indexed[group]
        finding = from_response({ "promises" => candidates }, evidence, member, expected: [ group ]).sole if candidates&.one?
        [ group, candidates&.first, finding ]
      rescue ArgumentError, KeyError
        [ group, nil, nil ]
      end
    end

    # A checked comparison already accounts for the intended result, the date
    # and the implementation stage. Reuse it when no personal finding settles the position.
    def self.city_finding(group, evidence)
      campaigns = group.map { |id| evidence.facts.fetch(id - 1) }
      headings = campaigns.pluck(:position).uniq
      return unless headings.one? && campaigns.none? { |fact| fact[:undertaking] == "personal_action" }
      heading = headings.first
      return if evidence.facts.any? do |fact|
        Array(fact[:opposed_positions]).include?(heading) ||
          (fact[:position] == heading && %w[contrary missed fell_short].include?(fact[:reviewed_status]))
      end
      outcomes = evidence.facts.select { |fact| fact[:position] == heading && fact[:kind] == "City outcome on campaign position" }
      latest = outcomes.select { |fact| %w[delivered advanced].include?(fact[:city_outcome]) && fact[:outcome_quote].present? }
        .max_by { |fact| [ fact.fetch(:dates).max, fact[:city_outcome] == "delivered" ? 1 : 0 ] }
      return unless latest
      return if outcomes.any? { |fact| %w[rejected deferred].include?(fact[:outcome_state]) && fact.fetch(:dates).max >= latest.fetch(:dates).max }

      step = evidence.facts.select { |fact| Array(fact[:advanced_positions]).include?(heading) }.max_by { |fact| fact.fetch(:dates).max }
      ids = group + [ latest, step ].compact.map { |fact| evidence.facts.index(fact) + 1 }
      { "heading" => heading, "label" => campaigns.first.fetch(:text), "quote" => campaigns.first.fetch(:promise_words).first.fetch("supporting_quote"),
        "status" => latest.fetch(:city_outcome) == "delivered" ? "city_result" : "city_progress",
        "reason" => latest.fetch(:outcome_reason), "outcome_quote" => latest.fetch(:outcome_quote),
        "member_step" => step && (step[:overview_text] || step.fetch(:text)),
        "facts" => ids.map { |id| evidence.fact_keys.fetch(id - 1) }, "sources" => ids.flat_map { |id| evidence.facts.fetch(id - 1).fetch(:sources) }.uniq }.compact
    end

    def self.city_updates?(status)
      %w[pending_review unresolved city_result city_progress pursued blocked].include?(status)
    end

    def self.for_publication(result, evidence, member)
      checked_groups(result, evidence, member).map do |group, _, finding|
        city = city_finding(group, evidence)
        next city if city && (!finding || city_updates?(finding["status"]))
        finding = nil if finding && %w[city_result city_progress].include?(finding["status"])
        next finding if finding
        facts = group.map { |id| evidence.facts.fetch(id - 1) }
        { "status" => "pending_review", "heading" => facts.pluck(:position).uniq.join(" / "), "label" => facts.first.fetch(:text),
          "quote" => facts.first.fetch(:promise_words).first.fetch("supporting_quote"),
          "reason" => "The link between this campaign position and the Council record still needs review.",
          "facts" => group.map { |id| evidence.fact_keys.fetch(id - 1) }, "sources" => facts.flat_map { |fact| fact.fetch(:sources) }.uniq }
      end
    end

    attr_reader :met, :contrary, :total, :net_points, :open_count, :partial_count

    def initialize(assessments, elapsed: nil)
      assessments = assessments.reject { |row| row["status"] == "pending_review" }
      @total = assessments.size
      @contrary = assessments.count { |row| row.fetch("status") == "contrary" }
      @met = assessments.count { |row| %w[met city_result].include?(row.fetch("status")) }
      @partial_count = assessments.count { |row| %w[pursued city_progress].include?(row.fetch("status")) }
      @elapsed = elapsed
      @open_count = assessments.count { |row| row.fetch("status") == "unresolved" }
      @net_points = assessments.sum { |row| points_for(row.fetch("status")) }
    end

    def points_for(status)
      return POINTS.fetch(status).to_r * (@elapsed || 0) if status == "unresolved"

      POINTS.fetch(status)
    end

    def self.point_label(status)
      points = POINTS.fetch(status)
      "#{format_points(points)} #{'point'.pluralize(points.abs)}"
    end

    def self.format_points(points)
      rounded = points.round(2)
      (rounded == rounded.to_i ? rounded.to_i : rounded.to_f).to_s.tr("-", "−")
    end

    def score
      (100 * net_points.to_r / total).round.clamp(0, 100) if total.positive?
    end
  end
end
