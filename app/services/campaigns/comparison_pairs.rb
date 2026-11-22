module Campaigns
  # Compare one proposal to one piece of evidence once, even when the candidate
  # repeated it in several sources. A narrowed alternative has its own verdict.
  module ComparisonPairs
    attr_reader :pairs

    def saved_match(pair, results)
      results[pair.fetch("key")] || results[@previous_topic_keys[pair.fetch("key")]]
    end

    def build_pairs(candidates)
      @groups = Hash.new { |h, k| h[k] = [] }
      @legacy = Hash.new { |h, k| h[k] = [] }
      @previous_topic_keys = {}
      @editorial = Set.new
      @pairs = candidates.map do |candidate|
        pair = yield(candidate)
        subject = candidate[:comparison_group] || candidate.fetch(:statement).id
        group = [ subject, pair["motion_id"], pair["evidence_kind"], pair["evidence"] ]
        @editorial << group if candidate[:editorial_reason]
        if candidate[:focus]
          original = pair.merge("key" => ActionInput.key(pair))
          @legacy[group] << [ original, candidate[:reuse_topic_match], Array(candidate[:prior_review_terms]) ]
          pair["focus"] = candidate[:focus]
        end
        pair["key"] = ActionInput.key(pair)
        @previous_topic_keys[pair.fetch("key")] = original.fetch("key") if candidate[:focus] && candidate[:reuse_topic_match]
        @groups[group] << pair
        pair
      end.sort_by { |pair| pair.fetch("key") }
    end

    def pairs_for_review(stages)
      completed = stages.select { |stage| stage.status == "completed" }
      rejected = completed.flat_map { |stage| stage.rejected_pairs.keys }.to_set
      results = completed.each_with_object({}) do |stage, saved|
        saved.merge!(stage.matches_by_key)
      end
      assigned = stages.flat_map(&:pair_keys).to_set
      @groups.filter_map do |group, mentions|
        next if @editorial.include?(group)
        reviewed = mentions.find { |pair| results.key?(pair.fetch("key")) }
        reviewed ||= @legacy[group].find do |original, reuse_topic_match, terms|
          key = original.fetch("key")
          match = results[key]
          next false unless match
          # Reuse a negative on a compound answer only for alternatives its reason addresses.
          reason = " #{match.fetch("reason").downcase.scan(/[[:alnum:]]+/).join(" ")} "
          rejected.include?(key) || (reuse_topic_match && match.fetch("status").in?(%w[direct not_direct])) ||
            (match.fetch("status") == "not_direct" && terms.any? { |term| reason.include?(" #{term} ") })
        end&.first
        reviewed || mentions.find { |pair| assigned.include?(pair.fetch("key")) } || mentions.first
      end.uniq { |pair| pair.fetch("key") }.sort_by { |pair| pair.fetch("key") }
    end
  end
end
