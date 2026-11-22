module Campaigns
  class TopicMatches
    class InvalidResponse < StandardError; end

    def initialize(context)
      @sequences = context.fetch("statements").map { |statement| statement.fetch("sequence") }.sort
      @topic_ids = context.fetch("topics").map { |topic| topic.fetch("id") }
    end

    def parse(response)
      data = JSON.parse(response)
      matches = data["matches"] if data.is_a?(Hash)
      raise InvalidResponse unless matches.is_a?(Array) && matches.all? { |match| match.is_a?(Hash) }
      sequences = matches.map { |match| match["sequence"] }
      raise InvalidResponse unless sequences.all? { |sequence| sequence.is_a?(Integer) } && sequences.sort == @sequences

      matches.each do |match|
        ids = match["topic_ids"]
        valid = match["status"].in?(%w[matched no_match unresolved]) && match["reason"].is_a?(String) && match["reason"].present? &&
          ids.is_a?(Array) && ids.all? { |id| id.is_a?(Integer) && @topic_ids.include?(id) } && ids.uniq == ids
        valid &&= match["status"] == "matched" ? ids.present? : ids.empty?
        raise InvalidResponse unless valid
      end
      { "matches" => matches.map { |match| match.slice("sequence", "status", "topic_ids", "reason") } }
    end
  end
end
