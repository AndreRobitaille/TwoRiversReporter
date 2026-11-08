module CouncilProfiles
  class FormalRecords
    class InvalidResponse < StandardError; end
    LABELS = { "filed" => "Complaint filed", "pending" => "Review pending", "hearing" => "Hearing recorded",
      "response" => "Response submitted", "finding" => "Finding issued", "no_violation" => "No violation found",
      "dismissed" => "Complaint dismissed", "withdrawn" => "Complaint withdrawn", "sanction" => "Sanction recorded",
      "appeal" => "Appeal filed", "amended" => "Decision amended", "vacated" => "Decision vacated" }.freeze
    ALLOWED = { "complaint" => %w[filed], "notice" => %w[filed pending hearing], "response" => %w[response],
      "decision" => %w[filed finding no_violation dismissed withdrawn sanction], "appeal" => %w[appeal],
      "correction" => LABELS.keys }.freeze

    def initialize(context)
      @context = context
    end

    def parse(response)
      data = JSON.parse(response)
      raise InvalidResponse unless data.is_a?(Hash) && data["complete"] == true && [ true, false ].include?(data["formal_record"]) &&
        data["events"].is_a?(Array) && data["events"].size <= 40
      raise InvalidResponse if data["formal_record"] == false && data["events"].any?
      { "formal_record" => data["formal_record"], "events" => data["events"].map { |event| validate(event) }.uniq }
    end

    private

    def validate(event)
      raise InvalidResponse unless event.is_a?(Hash) && ALLOWED.fetch(@context.fetch("record_kind"), []).include?(event["kind"]) &&
        event["quote"].is_a?(String) && event["quote"].length.between?(20, 2_000) &&
        event["subjects"].is_a?(Array) && event["subjects"].size.between?(1, 20) && event["subjects"].uniq == event["subjects"] &&
        (event["subjects"] - @context.fetch("subject_names")).empty? &&
        event["occurred_on"].is_a?(String) && event["occurred_on"].match?(/\A\d{4}-\d{2}-\d{2}\z/)
      quote = event.fetch("quote").split.join(" ")
      raise InvalidResponse unless @context.fetch("permitted_text").split.join(" ").include?(quote) &&
        Date.iso8601(event.fetch("occurred_on")) <= Date.iso8601(@context.fetch("published_on")) &&
        event.fetch("subjects").all? { |name| quote.match?(/(?<![[:alnum:]])#{Regexp.escape(name)}(?![[:alnum:]])/i) }
      event.slice("kind", "occurred_on", "subjects").merge("quote" => quote)
    rescue ArgumentError
      raise InvalidResponse
    end
  end
end
