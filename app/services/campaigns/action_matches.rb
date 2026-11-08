module Campaigns
  class ActionMatches
    class InvalidResponse < StandardError; end

    def initialize(context)
      @keys = context.fetch("pairs").map { |pair| pair.fetch("key") }.sort
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
          quote = match[quote_field]
          valid &&= quote.is_a?(String) && quote.length.between?(20, 2_000) && @quotes.fetch(match.fetch("key")).include?(normalize(quote))
        end
        raise InvalidResponse unless valid
      end
      { "matches" => matches.map { |match| match.slice("key", "status", "reason", quote_field) } }
    end

    private

    def quote_field
      @issue_evidence ? "source_quote" : "minutes_quote"
    end

    def normalize(text)
      text.split.join(" ")
    end
  end
end
