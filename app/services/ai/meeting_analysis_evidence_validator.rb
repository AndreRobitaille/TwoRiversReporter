module Ai
  class MeetingAnalysisEvidenceValidator
    def initialize(document_text:, motion_context:, participant_context: nil)
      @sources = [ document_text, motion_context ].map { |text| normalize(text) }
      @participant_names = participant_context.to_s.scan(/\b\p{Lu}[\p{L}'’-]+(?:\s+\p{Lu}[\p{L}'’-]+)+\b/)
      @name_tokens = @participant_names.flat_map(&:split).map(&:downcase).select { |part| part.length >= 4 }.uniq
      @vote_sources = @sources.map { |text| canonical_vote_text(text) }
    end

    def validate(content)
      data = JSON.parse(content)
      return content unless data.is_a?(Hash) && data["item_details"].is_a?(Array)

      data["item_details"].each do |item|
        next unless item.is_a?(Hash)

        item["vote"] = nil unless supported_vote?(item["vote"], item["vote_evidence"])
        validate_motion(item)
      end
      validate_highlight_votes(data)
      data.to_json
    rescue JSON::ParserError
      content
    end

    private

    def validate_highlight_votes(data)
      validated_items = data["item_details"].select { |item| item.is_a?(Hash) && item["agenda_item_id"].is_a?(Integer) }
        .group_by { |item| item["agenda_item_id"] }
      Array(data["highlights"]).each do |highlight|
        next unless highlight.is_a?(Hash) && highlight["agenda_item_id"].is_a?(Integer)

        matches = validated_items[highlight["agenda_item_id"]]
        highlight["vote"] = matches.first["vote"] if matches&.one?
      end
    end

    def validate_motion(item)
      motion = item["motion"]
      return unless motion.is_a?(Hash)

      evidence = item["motion_evidence"]
      evidence = {} unless evidence.is_a?(Hash)
      %w[mover seconder].each do |role|
        motion[role] = nil unless supported_name?(motion[role], evidence[role], role)
      end
      %w[no_votes absent_members].each do |role|
        names = motion[role]
        next unless names.is_a?(Array)
        if names.empty?
          motion[role] = nil if role == "no_votes" && item["vote"].to_s.match?(/[-–][1-9]\d*\z/)
          next
        end

        quotes = evidence[role]
        supported = quotes.is_a?(Array) && quotes.length == names.length &&
          names.zip(quotes).all? { |name, quote| supported_name?(name, quote, role) }
        motion[role] = nil unless supported
      end
    end

    def supported_name?(name, quote, role)
      return false unless name.is_a?(String) && name.present? && source_quote?(quote)
      return false if quote.length > 500

      first_name, last_name = name.split.values_at(0, -1)
      # A unique surname can survive a garbled first name in captions.
      # Shared surnames cannot distinguish participants from one another.
      surname_matches = @participant_names.count { |participant| participant.split.last.casecmp?(last_name) }
      identifiers = [ first_name ]
      identifiers << last_name if surname_matches <= 1
      identity = "\\b(?:#{identifiers.uniq.map { |part| Regexp.escape(part.downcase) }.join('|')})\\b"
      text = normalize(quote)

      case role
      when "mover"
        text.match?(/#{identity}.{0,40}\bmoved\b/) ||
          text.match?(/#{identity}.{0,40}\b(?:made|make)\b.{0,30}\bmotion\b/) ||
          text.match?(/\bmotion\b.{0,180}\bthank you[\s,]+#{identity}/)
      when "seconder"
        # "I'll second Mark" addresses the mover; it does not name the speaker.
        text.match?(/#{identity}.{0,40}\bseconded\b/) ||
          text.match?(/\bsecond\b.{0,180}\bthank you[\s,]+#{identity}/)
      when "no_votes"
        match = text.match(/#{identity}(.{0,100}?)\b(?:no|nay|against)\b/)
        match.present? && !match[1].match?(/\b(?:aye|yes)\b/)
      when "absent_members"
        text.match?(/#{identity}.{0,60}\babsent\b/)
      end
    end

    def supported_vote?(vote, quote)
      return false unless vote.is_a?(String) && quote.is_a?(String) && quote.present?
      normalized_quote = canonical_vote_text(quote)
      return false unless @vote_sources.any? { |source| " #{source} ".include?(" #{normalized_quote} ") }

      tally = vote.match(/\A(\d+)\s*[-–]\s*(\d+)\z/)
      return false unless tally

      ayes, noes = tally.captures.map(&:to_i)
      return true if quote.match?(/\b#{ayes}\s*(?:[-–]|to)\s*#{noes}\b/i)

      # A voice vote's collective "Aye" cannot establish a numeric tally.
      # Captions can omit or garble the roll-call introduction. Multiple
      # named responses also distinguish a roll call from a collective aye.
      named_responses = quote.scan(/\b\p{L}[\p{L}'’-]*\s+\p{L}[\p{L}'’-]*[.,?:;\s]+(?:aye|yes|no|nay)\b/i).length
      return false unless quote.match?(/\broll\b/i) || named_responses >= 2

      quote.scan(/\b(?:aye|yes)\b/i).length == ayes &&
        quote.scan(/\b(?:no|nay)\b/i).length == noes
    end

    def source_quote?(quote)
      return false unless quote.is_a?(String) && quote.present?

      normalized = normalize(quote)
      @sources.any? { |source| source.include?(normalized) }
    end

    def canonical_vote_text(text)
      text.downcase.scan(/[\p{L}\p{N}]+/).map do |token|
        # Quote formatting and a one-letter name variation do not change
        # individual responses. Voting words and numbers remain exact.
        next token if @name_tokens.include?(token)

        candidates = @name_tokens.select { |name| one_letter_difference?(token, name) }
        candidates.one? ? candidates.first : token
      end.join(" ")
    end

    def one_letter_difference?(left, right)
      return false if (left.length - right.length).abs > 1
      return left.chars.zip(right.chars).count { |a, b| a != b } == 1 if left.length == right.length

      shorter, longer = [ left, right ].sort_by(&:length)
      index = shorter.chars.each_index.find { |i| shorter[i] != longer[i] } || shorter.length
      shorter[index..] == longer[(index + 1)..]
    end

    def normalize(text)
      text.to_s.gsub(/\s+/, " ").strip.downcase
    end
  end
end
