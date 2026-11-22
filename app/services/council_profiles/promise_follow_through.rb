module CouncilProfiles
  class PromiseFollowThrough
    LABELS = {
      "contrary" => "Acted against the position", "met" => "Documented result", "pursued" => "Acted, result unconfirmed", "blocked" => "Acted and was outvoted",
      "missed" => "Missed opportunity", "fell_short" => "Fell short", "unresolved" => "Unfulfilled in the public record"
    }.freeze

    MATERIAL_EFFECTS = %w[binding_decision committed_resources operating_program documented_result].freeze

    def self.from_response(result, evidence, member)
      expected = position_groups(evidence.facts)
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
          validate_judgment!(group, relevant, headings, member)
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
      text = attribution if fact[:kind] == "Minutes excerpt"
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

    attr_reader :met, :contrary, :total

    def initialize(assessments)
      @total = assessments.size
      @contrary = assessments.count { |row| row.fetch("status") == "contrary" }
      @met = assessments.count { |row| row.fetch("status") == "met" }
    end

    def net_points
      met - contrary
    end

    def percentage
      (100.0 * net_points / total).round if total.positive?
    end

    def lead
      return if total.zero?
      return "#{met} #{'result'.pluralize(met)} − #{contrary} #{'reversal'.pluralize(contrary)} = #{net_points} of #{total} points." if contrary.positive?
      "Results on #{met} of #{total} campaign #{'position'.pluralize(total)}."
    end
  end
end
