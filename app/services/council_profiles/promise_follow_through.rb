module CouncilProfiles
  class PromiseFollowThrough
    LABELS = { "met" => "Followed through", "fell_short" => "Fell short", "unresolved" => "Unresolved" }.freeze

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
        if status == "met" && !MATERIAL_EFFECTS.include?(group["material_effect"])
          raise ArgumentError, "Follow-through needs a material effect"
        end
        personal = records.any? do |id|
          fact = evidence.facts[id - 1]
          next false if fact[:position] && positions.none? { |ref| evidence.facts[ref - 1][:position] == fact[:position] }
          fact[:kind].start_with?("Member ") || (fact[:kind] == "Public record" && named_action?(fact[:text], [ member.name.split.last ])) ||
            attributed_excerpt?(fact, group["attribution"])
        end
        raise ArgumentError, "Promise judgment needs attributed work" unless status == "unresolved" || personal

        ids = positions + records
        campaign = evidence.facts.fetch(positions.first - 1)
        { "heading" => positions.map { |id| evidence.facts[id - 1][:position] }.compact.uniq.join(" / "), "label" => campaign.fetch(:text), "quote" => campaign.fetch(:promise_words).first.fetch("supporting_quote"), "status" => status, "reason" => reason.strip,
          "facts" => ids.map { |id| evidence.fact_keys.fetch(id - 1) }.uniq,
          "sources" => ids.flat_map { |id| evidence.facts.fetch(id - 1).fetch(:sources) }.uniq }
      end
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

    attr_reader :met, :total

    def initialize(assessments)
      @total = assessments.size
      @met = assessments.count { |row| row.fetch("status") == "met" }
    end

    def percentage
      (100.0 * met / total).round if total.positive?
    end

    def lead(name)
      return if total.zero?
      return "The record shows follow-through on #{met} of #{total} tracked campaign #{'promise'.pluralize(total)}." if total < 3

      if 3 * met < total
        "The record shows #{name} has fulfilled only #{met} of #{total} campaign promises so far."
      elsif 3 * met > 2 * total
        "#{name} has followed through on #{met} of #{total} campaign promises."
      else
        "#{name}’s record on campaign promises is mixed, with #{met} of #{total} fulfilled so far."
      end
    end
  end
end
