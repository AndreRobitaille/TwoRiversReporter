module Campaigns
  # Both the desk and the importer address a speaker's passage by word index.
  class ForumCaptions
    TIME = /(?:(\d+):)?(\d{2}):(\d{2})[.,](\d{3})/
    TIMING = /\A\s*(#{TIME.source})\s+-->\s+(#{TIME.source})(?:\s|\z)/

    def self.words(raw)
      raise PreparedForum::InvalidFile, "Captions must be UTF-8." unless raw.valid_encoding?

      rolling = raw.lstrip.start_with?("WEBVTT") && raw.include?("align:start position:0%")
      words = []
      previous_end = -1
      raw.delete("\r").split(/\n\s*\n/).each do |block|
        lines = block.lines.map(&:chomp)
        index = lines.index { |line| line.include?("-->") }
        next unless index

        timing = TIMING.match(lines[index])
        raise PreparedForum::InvalidFile, "A caption has invalid timing." unless timing
        start_ms = milliseconds(timing[1])
        end_ms = milliseconds(timing[6])
        raise PreparedForum::InvalidFile, "A caption ends before it starts." if end_ms < start_ms

        tokens = []
        position = start_ms
        lines.drop(index + 1).join(" ").scan(/<([^>]*)>|([^<]+)/) do |tag, text|
          if text
            decoded = text.include?("&") ? Nokogiri::HTML5.fragment(text).text : text
            decoded.split(/[[:space:]]+/).reject(&:empty?).each do |word|
              tokens << { text: word, start_ms: position, end_ms: end_ms }
            end
          elsif tag.match?(/\A#{TIME.source}\z/)
            position = milliseconds(tag).clamp(start_ms, end_ms)
          end
        end
        overlap = 0
        if rolling && start_ms < previous_end + 100
          max = [ words.size, tokens.size, 200 ].min
          overlap = max.downto(1).find { |n| words.last(n).pluck(:text) == tokens.first(n).pluck(:text) } || 0
        end
        words.concat(tokens.drop(overlap))
        previous_end = end_ms
      end
      raise PreparedForum::InvalidFile, "Choose an SRT or VTT with timestamped captions." if words.empty?
      words.each_cons(2) do |word, following|
        word[:end_ms] = [ word[:end_ms], following[:start_ms] ].min if following[:start_ms] > word[:start_ms]
      end
      words
    end

    def self.milliseconds(time)
      hours, minutes, seconds, millis = TIME.match(time).captures
      ((hours.to_i * 60 + minutes.to_i) * 60 + seconds.to_i) * 1000 + millis.to_i
    end
  end
end
