module Campaigns
  class ActionMatches
    class InvalidResponse < StandardError; end

    def initialize(context)
      @keys = context.fetch("pairs").map { |pair| pair.fetch("key") }.sort
      @minutes = normalize(context.fetch("minutes"))
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
          quote = match["minutes_quote"]
          valid &&= quote.is_a?(String) && quote.length.between?(20, 2_000) && @minutes.include?(normalize(quote))
        end
        raise InvalidResponse unless valid
      end
      { "matches" => matches.map { |match| match.slice("key", "status", "reason", "minutes_quote") } }
    end

    private

    def normalize(text)
      text.split.join(" ")
    end
  end
end
