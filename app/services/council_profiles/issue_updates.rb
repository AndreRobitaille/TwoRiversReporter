module CouncilProfiles
  class IssueUpdates
    class InvalidResponse < StandardError; end
    STATUSES = %w[proposed authorized funded underway completed rejected deferred unresolved].freeze

    def initialize(context)
      @context = context
    end

    def parse(response)
      data = JSON.parse(response)
      rows = data["updates"] if data.is_a?(Hash)
      raise InvalidResponse unless data.is_a?(Hash) && data["complete"] == true &&
        rows.is_a?(Array) && rows.size <= 40 && rows.all? { |row| row.is_a?(Hash) }

      { "updates" => rows.map { |row| validate(row) }.uniq }
    end

    private

    def validate(row)
      item = @context.fetch("agenda").find { |item| item["id"] == row["agenda_item_id"] }
      ids = row["topic_ids"]
      valid = item && ids.is_a?(Array) && ids.any? && ids.uniq == ids &&
        (ids - item.fetch("topics").map { |topic| topic.fetch("id") }).empty? &&
        STATUSES.include?(row["status"]) && text?(row["subject"], 100) && text?(row["summary"], 240) &&
        (row["conditions"].nil? || text?(row["conditions"], 300)) && text?(row["quote"], 2_000)
      raise InvalidResponse unless valid
      quote = row.fetch("quote").split.join(" ")
      raise InvalidResponse unless quote.length >= 20 && @context.fetch("text").split.join(" ").include?(quote)
      date = row["occurred_on"]
      if date
        raise InvalidResponse unless date.is_a?(String) && date.match?(/\A\d{4}-\d{2}-\d{2}\z/) &&
          Date.iso8601(date) <= Date.iso8601(@context.fetch("reported_on"))
      end
      row.slice("agenda_item_id", "topic_ids", "subject", "status", "summary", "conditions", "occurred_on").merge("quote" => quote)
    rescue ArgumentError
      raise InvalidResponse
    end

    def text?(value, maximum)
      value.is_a?(String) && value.strip.present? && value.length <= maximum
    end
  end
end
