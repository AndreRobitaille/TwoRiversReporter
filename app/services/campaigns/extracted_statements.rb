module Campaigns
  # Text occurrence checks locate evidence; they do not verify interpretation or
  # resolve a candidate to a serving official. The whole source is analyzed once.
  class ExtractedStatements
    class InvalidResponse < StandardError; end
    KINDS = %w[commitment priority position retrospective_claim].freeze

    def initialize(text, speaker_segments: nil)
      @text = text
      @speaker_segments = speaker_segments
    end

    def parse(response)
      data = JSON.parse(response)
      raise InvalidResponse unless data.is_a?(Hash)

      participants = rows(data, "participants").map do |participant|
        name = participant["name"]
        name_quote = participant["name_quote"]
        attribution = name.is_a?(String) && name.present? && name_quote.is_a?(String) &&
          name_quote.include?(name) && locate(name_quote)
        answers = rows(participant, "answers").map { |answer| check_answer(answer, attribution, name) }
        participant.slice("name", "name_quote").merge("answers" => answers)
      end
      gaps = rows(data, "coverage_gaps").map do |gap|
        gap.slice("description", "supporting_quote").merge("location" => locate(gap["supporting_quote"]))
      end
      answers = participants.flat_map { |participant| participant.fetch("answers") }
      statements = answers.flat_map { |answer| answer.fetch("statements") }
      { "participants" => participants, "coverage_gaps" => gaps,
        "counts" => { "participants" => participants.size, "answers" => answers.size,
          "statements" => statements.size, "located_statements" => statements.count { |s| s["location_status"] == "located" },
          "unresolved_statements" => statements.count { |s| s["location_status"] == "unresolved" }, "reported_gaps" => gaps.size } }
    end

    private

    def rows(object, key)
      value = object[key]
      raise InvalidResponse unless value.is_a?(Array) && value.all? { |row| row.is_a?(Hash) }
      value
    end

    def check_answer(answer, attribution, name)
      unless %w[question passage].all? { |key| answer[key].is_a?(String) && answer[key].present? }
        raise InvalidResponse
      end

      question_location = locate(answer["question"])
      passage_location = locate(answer["passage"])
      statements = rows(answer, "statements").map do |statement|
        quote = statement["supporting_quote"]
        location = if passage_location
          locate(quote, text: answer["passage"], offset: passage_location.fetch("start")) ||
            locate_forum_excerpt(quote, answer["passage"], passage_location.fetch("start"))
        end
        exception = if !attribution || (location && !speaker_matches?(name, location))
          "unresolved_attribution"
        elsif !question_location || !passage_location || !location
          "unresolved_source_passage"
        elsif !KINDS.include?(statement["kind"]) || !statement["summary"].is_a?(String) || statement["summary"].blank?
          "invalid_statement"
        end
        statement.slice("kind", "summary", "supporting_quote", "conditions", "timeframe").merge(
          "supporting_quote" => exception ? quote : @text[location.fetch("start")...location.fetch("end")],
          "location_status" => exception ? "unresolved" : "located", "exception" => exception, "location" => location)
      end
      answer.slice("question", "passage").merge("question_location" => question_location,
        "passage_location" => passage_location, "statements" => statements)
    end

    def speaker_matches?(name, location)
      return true unless @speaker_segments

      @speaker_segments.any? do |segment|
        segment["attribution"] == "reviewer_verified" && segment["speaker"]&.casecmp?(name) &&
          location.fetch("start") >= segment.fetch("text_start") && location.fetch("end") <= segment.fetch("text_end")
      end
    end

    # Expand an abbreviated provider excerpt to the actual contiguous passage,
    # including omitted qualifications. Speaker validation still covers it all.
    def locate_forum_excerpt(quote, passage, offset)
      return unless @speaker_segments && quote.is_a?(String)
      fragments = quote.split(/\.{3}|…/).map(&:strip)
      return unless fragments.size > 1 && fragments.all?(&:present?)
      locations = fragments.map { |fragment| locate(fragment, text: passage) }
      return unless locations.all? && locations.each_cons(2).all? { |left, right| left.fetch("end") <= right.fetch("start") }

      { "start" => offset + locations.first.fetch("start"), "end" => offset + locations.last.fetch("end") }
    end

    def locate(quote, text: @text, offset: 0)
      return unless quote.is_a?(String) && quote.present?
      start = text.index(quote)
      return unless start && !text.index(quote, start + 1)

      { "start" => offset + start, "end" => offset + start + quote.length }
    end
  end
end
