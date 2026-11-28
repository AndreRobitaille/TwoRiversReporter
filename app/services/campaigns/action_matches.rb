module Campaigns
  class ActionMatches
    class InvalidResponse < StandardError; end

    def initialize(context)
      @pairs = context.fetch("pairs").index_by { |pair| pair.fetch("key") }
      @keys = @pairs.keys.sort
      @reported_on = context["reported_on"]
      @issue_evidence = context["rules"] == IssueEvidenceInput::RULES
      @quotes = if @issue_evidence
        context.fetch("pairs").to_h { |pair| [ pair.fetch("key"), normalize(pair.fetch("evidence").fetch("quote")) ] }
      else
        @keys.to_h { |key| [ key, normalize(context.fetch("minutes")) ] }
      end
    end

    def parse(response)
      data = JSON.parse(response)
      matches = data["matches"] if data.is_a?(Hash)
      raise InvalidResponse unless matches.is_a?(Array) && matches.all? { |match| match.is_a?(Hash) }
      keys = matches.map { |match| match["key"] }
      raise InvalidResponse unless keys.all? { |key| key.is_a?(String) } && keys.sort == @keys

      matches.each do |match|
        valid = match["status"].in?(%w[direct not_direct insufficient_evidence]) &&
          match["reason"].is_a?(String) && match["reason"].present? && match["reason"].length <= 1_000
        if match["status"] == "direct"
          valid &&= match[effect_field].in?(%w[advances opposes unclear]) if match.key?(effect_field)
          if match["city_outcome"].present?
            pair = @pairs.fetch(match.fetch("key"))
            valid &&= @issue_evidence && pair["evidence_kind"] == "outcome" && valid_city_outcome?(match, pair)
          end
          quote = match[quote_field]
          valid &&= quote.is_a?(String) && quote.length <= 2_000 && normalize(quote).length >= 20 &&
            @quotes.fetch(match.fetch("key")).include?(normalize(quote))
        end
        raise InvalidResponse unless valid
      end
      { "matches" => matches.map do |match|
        row = match.slice("key", "status", "reason", quote_field)
        row.merge!(match.slice(effect_field)) if match["status"] == "direct"
        row.merge!(match.slice("city_outcome", "outcome_on", "position_words", "undertaking")) if match["status"] == "direct" && match["city_outcome"].present?
        row
      end }
    end

    private

    def valid_city_outcome?(match, pair)
      return false unless %w[delivered advanced].include?(match["city_outcome"]) && match["outcome_on"].is_a?(String)
      return false if pair.dig("platform_test", "undertaking") == "personal_action"
      words = match["position_words"]
      return false unless words.is_a?(String) && words.strip.length >= 5 && pair.dig("statement", "supporting_quote").to_s.include?(words) &&
        match["undertaking"] == "city_outcome"
      date = Date.iso8601(match["outcome_on"])
      evidence = pair.fetch("evidence")
      return false if evidence["occurred_on"] && date.iso8601 != evidence["occurred_on"]
      return false if %w[proposed deferred rejected unresolved].include?(evidence["status"])
      date <= Date.iso8601(@reported_on)
    rescue Date::Error, TypeError
      false
    end

    def effect_field
      @issue_evidence ? "action_effect" : "motion_effect"
    end

    def quote_field
      @issue_evidence ? "source_quote" : "minutes_quote"
    end

    def normalize(text)
      text.split.join(" ")
    end
  end
end
