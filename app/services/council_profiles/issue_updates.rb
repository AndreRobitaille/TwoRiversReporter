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

      result = { "updates" => rows.map { |row| validate(row) }.uniq }
      if @context["schema_version"].to_i >= 2
        actions = data["actions"]
        raise InvalidResponse unless actions.is_a?(Array) && actions.size <= 40
        result["actions"] = actions.map { |row| validate_action(row) }.uniq
      end
      if @context["schema_version"] == 3
        recommendations = data["recommendations"]
        raise InvalidResponse unless recommendations.is_a?(Array) && recommendations.size <= 40
        result["recommendations"] = recommendations.map { |row| validate_recommendation(row) }.uniq
      end
      result
    end

    private

    def validate_recommendation(row)
      raise InvalidResponse unless row.is_a?(Hash) && text?(row["author"], 120) &&
        (row["role"].nil? || text?(row["role"], 120)) &&
        row["author_kind"].in?(%w[city_manager staff_member department advisory_body unspecified_staff]) &&
        row["position"].in?(%w[support oppose]) && text?(row["proposal"], 2_000) &&
        (row["conditions"].nil? || text?(row["conditions"], 300)) &&
        row["timing"].in?(%w[before_vote after_vote unclear])
      evidence = validate_evidence(row.merge("occurred_on" => row["made_on"]))
      quote = evidence.fetch("quote").downcase
      raise InvalidResponse unless quote.include?(row.fetch("author").split.join(" ").downcase) &&
        quote.include?(row.fetch("proposal").split.join(" ").downcase) &&
        (row["role"].nil? || quote.include?(row["role"].split.join(" ").downcase))
      evidence.except("occurred_on").merge(row.slice("author", "role", "author_kind", "position", "proposal", "conditions", "made_on", "timing"))
    end

    def validate_action(row)
      raise InvalidResponse unless row.is_a?(Hash) &&
        row["kind"].in?(%w[proposal amendment analysis_request agenda_request opposition follow_up]) &&
        text?(row["speaker"], 120) && text?(row["summary"], 180) && row["occurred_on"].present?
      # Share source, topic and date validation with milestones. A located quote
      # does not independently establish the model's semantic interpretation.
      evidence = validate_evidence(row)
      speaker = row.fetch("speaker").split.join(" ")
      raise InvalidResponse unless evidence.fetch("quote").match?(/(?<![[:alnum:]])#{Regexp.escape(speaker)}(?![[:alnum:]])/i)
      evidence.merge(row.slice("summary", "kind"), "speaker" => speaker)
    end

    def validate(row)
      raise InvalidResponse unless STATUSES.include?(row["status"]) && text?(row["subject"], 100) &&
        text?(row["summary"], 240) && (row["conditions"].nil? || text?(row["conditions"], 300))
      validate_evidence(row).merge(row.slice("subject", "status", "summary", "conditions"))
    end

    def validate_evidence(row)
      item = @context.fetch("agenda").find { |item| item["id"] == row["agenda_item_id"] }
      ids = row["topic_ids"]
      valid = item && ids.is_a?(Array) && ids.any? && ids.uniq == ids &&
        (ids - item.fetch("topics").map { |topic| topic.fetch("id") }).empty? && text?(row["quote"], 2_000)
      raise InvalidResponse unless valid
      quote = row.fetch("quote").split.join(" ")
      raise InvalidResponse unless quote.length >= 20 && @context.fetch("text").split.join(" ").include?(quote)
      date = row["occurred_on"]
      if date
        raise InvalidResponse unless date.is_a?(String) && date.match?(/\A\d{4}-\d{2}-\d{2}\z/) &&
          Date.iso8601(date) <= Date.iso8601(@context.fetch("reported_on"))
      end
      row.slice("agenda_item_id", "topic_ids", "occurred_on").merge("quote" => quote)
    rescue ArgumentError
      raise InvalidResponse
    end

    def text?(value, maximum)
      value.is_a?(String) && value.strip.present? && value.length <= maximum
    end
  end
end
