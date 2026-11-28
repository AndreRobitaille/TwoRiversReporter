module Campaigns
  # Text occurrence checks locate evidence; they do not verify interpretation or
  # resolve a candidate to a serving official. The whole source is analyzed once.
  class ExtractedStatements
    class InvalidResponse < StandardError; end
    KINDS = %w[commitment priority position retrospective_claim].freeze

    def self.for_version(version)
      names = ElectionBackfill.candidates_on(version.election_on) unless version.forum?
      new(version.body, speaker_segments: version.prepared_transcript["segments"], candidate_names: names)
    end

    def initialize(text, speaker_segments: nil, candidate_names: nil)
      @text = text
      @speaker_segments = speaker_segments
      @candidate_names = candidate_names
    end

    def parse(response)
      validate(JSON.parse(response))
    end

    def validate(data)
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
      if @speaker_segments && answer.key?("answer_turn")
        answer, question_location, passage_location, attribution = referenced_answer(answer, name)
      else
        unless %w[question passage].all? { |key| answer[key].is_a?(String) && answer[key].present? }
          raise InvalidResponse
        end
        passage_location = locate(answer["passage"])
        question_location = locate(answer["question"]) || questionnaire_question(answer["question"], name, attribution, passage_location)
      end

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
        heading = statement["comparison_heading"]
        fields = statement.slice("kind", "summary", "supporting_quote", "conditions", "timeframe")
        if statement.key?("comparison_heading") && (heading.nil? || (heading.is_a?(String) && heading.strip.length.between?(1, 140)))
          # Recent extractions give the speaker's own action clause. A rejected
          # clause leaves the passage in the source archive outside the platform.
          if statement.key?("action_quote")
            clause = statement["action_quote"]
            supported = clause.is_a?(String) && clause.strip.length >= 5 && quote.to_s.include?(clause)
            fields["action_quote"] = clause if supported
            heading = nil unless supported
          end
          fields["comparison_heading"] = heading&.strip
        end
        fields.merge(
          "supporting_quote" => exception ? quote : @text[location.fetch("start")...location.fetch("end")],
          "location_status" => exception ? "unresolved" : "located", "exception" => exception, "location" => location)
      end
      answer.slice("question", "passage", "question_turn", "answer_turn", "question_excerpt").merge("question_location" => question_location,
        "passage_location" => passage_location, "statements" => statements)
    end

    def referenced_answer(answer, name)
      question, passage = %w[question_turn answer_turn].map do |key|
        number = answer[key]
        raise InvalidResponse unless number.is_a?(Integer) && number.between?(1, @speaker_segments.size)
        @speaker_segments.fetch(number - 1)
      end
      raise InvalidResponse if answer.fetch("question_turn") > answer.fetch("answer_turn")
      full_question = turn_location(question)
      excerpt = locate(answer["question_excerpt"], text: question.fetch("text"), offset: full_question.fetch("start")) || full_question
      text = @text[excerpt.fetch("start")...excerpt.fetch("end")]
      attributed = name.present? && passage["attribution"] == "reviewer_verified" && passage["speaker"] == name
      [ answer.merge("question" => text, "passage" => passage.fetch("text")), excerpt, turn_location(passage), attributed ]
    end

    def turn_location(segment)
      start = segment.fetch("text_start")
      finish = segment.fetch("text_end")
      raise InvalidResponse unless @text[start...finish] == segment.fetch("text")
      { "start" => start, "end" => finish }
    end

    # A newspaper can print the same question beneath every candidate's name.
    # The name evidence and the entire answer must belong to that candidate's section.
    def questionnaire_question(question, name, attribution, passage)
      return unless @candidate_names.present? && attribution && passage
      section = questionnaire_sections[name]
      return unless section && section.cover?(attribution.fetch("start")) && section.cover?(attribution.fetch("end") - 1) &&
        section.cover?(passage.fetch("start")) && section.cover?(passage.fetch("end") - 1)

      location = locate(question, text: @text[section], offset: section.begin)
      location if location && location.fetch("start") <= passage.fetch("start")
    end

    def questionnaire_sections
      @questionnaire_sections ||= begin
        headings = @text.to_enum(:scan, /^#{Regexp.union(@candidate_names)}\r?$/).map { Regexp.last_match }
        if headings.map { |match| match[0].strip }.sort == @candidate_names.sort
          headings.map.with_index.to_h do |match, index|
            [ match[0].strip, match.begin(0)...(headings[index + 1]&.begin(0) || @text.size) ]
          end
        else
          {}
        end
      end
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
