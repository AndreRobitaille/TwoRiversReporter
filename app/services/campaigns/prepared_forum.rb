require "cgi"
require "digest"
require "json"

module Campaigns
  # Adapts externally labeled captions. It neither transcribes nor infers speakers.
  class PreparedForum
    class InvalidFile < StandardError; end
    MAX_BYTES = 2_000_000

    def initialize(raw_json, verified_by:, gaps_are_moderator: false)
      @raw_json = raw_json.to_s.dup.force_encoding(Encoding::UTF_8)
      @verified_by = verified_by
      @gaps_are_moderator = gaps_are_moderator
    end

    def call
      check(@raw_json.bytesize <= MAX_BYTES, "The speaker file must be smaller than 2 MB.")
      check(@raw_json.valid_encoding?, "The speaker file must contain UTF-8 JSON.")
      @data = JSON.parse(@raw_json)
      check(@data.is_a?(Hash) && @data.values_at("format", "version", "parserVersion") == [ "forum-speaker-desk", 1, 1 ],
        "Use a forum-speaker-desk version 1 export.")
      check(@verified_by&.persisted?, "A reviewer must verify the speaker labels.")
      check(@data["title"].is_a?(String) && @data["title"].present?, "The file needs a forum title.")
      check(@data["sourceUrl"].is_a?(String), "The file needs a recording link.")
      check(@data["captions"].is_a?(String), "The file must include its original captions.")
      check(Digest::SHA256.hexdigest(@data["captions"]) == @data["sourceSha256"], "The captions do not match the file's source hash.")
      names = @data["names"]
      check(names.is_a?(Array) && names.any? && names.all? { |name| name.is_a?(String) && name.present? }, "The file needs speaker names.")
      words = caption_words
      check(words.size == @data["wordCount"], "The parsed word count does not match the speaker labels.")
      segments = speaker_segments(words, names)
      body = +""
      segments.each do |segment|
        body << "\n\n" unless body.empty?
        speaker = segment["speaker"] || "Unattributed speaker"
        body << "[#{timestamp(segment['start_ms'])} - #{timestamp(segment['end_ms'])}] #{speaker}\n"
        segment["text_start"] = body.length
        body << segment.fetch("text")
        segment["text_end"] = body.length
      end
      { title: @data["title"], source_url: @data["sourceUrl"], body: body, coverage: "full_transcript",
        prepared_transcript: { "original_json" => @raw_json, "sha256" => Digest::SHA256.hexdigest(@raw_json),
          "reviewed_by_id" => @verified_by.id, "speaker_attribution_verified" => true,
          "gaps_are_moderator" => @gaps_are_moderator, "transcription_verified" => @data["transcriptionVerified"] == true,
          "timing_basis" => @data["timingBasis"].to_s, "word_count" => words.size, "segments" => segments } }
    rescue JSON::ParserError
      raise InvalidFile, "The uploaded file is not valid JSON."
    end

    private

    def caption_words
      words = []
      @data["captions"].split(/\n\s*\n/).each do |block|
        lines = block.lines.map(&:chomp)
        timing_index = lines.index { |line| line.include?("-->") }
        next unless timing_index

        times = lines[timing_index].scan(/\d{2}:\d{2}:\d{2}\.\d{3}/).map { |time| milliseconds(time) }
        check(times.size == 2 && times.first <= times.last, "A caption has invalid timing.")
        text = CGI.unescapeHTML(lines.drop(timing_index + 1).join(" ").gsub(/<[^>]*>/, "")).split
        overlap = [ words.size, text.size ].min.downto(1).find { |size| words.last(size).pluck(:text) == text.first(size) } || 0
        words.concat(text.drop(overlap).map { |word| { text: word, start_ms: times.first, end_ms: times.last } })
      end
      check(words.any?, "The file contains no caption words.")
      words
    end

    def speaker_segments(words, names)
      annotations = @data["annotations"]
      check(annotations.is_a?(Array) && annotations.any?, "The file needs speaker labels.")
      segments = []
      position = 0
      annotations.each do |annotation|
        check(annotation.is_a?(Hash), "A speaker label is invalid.")
        start, finish, speaker = annotation.values_at("start", "end", "speaker")
        check([ start, finish, speaker ].all? { |value| value.is_a?(Integer) } &&
          position <= start && start < finish && finish <= words.size && speaker.between?(0, names.size - 1),
          "Speaker labels must be ordered, non-overlapping word ranges.")
        segments << segment(words, position, start, gap_speaker, gap_attribution) if start > position
        segments << segment(words, start, finish, names[speaker], "reviewer_verified")
        position = finish
      end
      segments << segment(words, position, words.size, gap_speaker, gap_attribution) if position < words.size
      segments
    end

    def gap_speaker
      "Moderator" if @gaps_are_moderator
    end

    def gap_attribution
      @gaps_are_moderator ? "reviewer_identified_moderator_filler" : "unattributed"
    end

    def segment(words, first, last, speaker, attribution)
      { "word_start" => first, "word_end" => last, "speaker" => speaker, "attribution" => attribution,
        "start_ms" => words[first][:start_ms], "end_ms" => words[last - 1][:end_ms],
        "text" => words[first...last].pluck(:text).join(" ") }
    end

    def milliseconds(time)
      hours, minutes, seconds = time.split(":")
      ((hours.to_i * 3600 + minutes.to_i * 60 + seconds.to_f) * 1000).round
    end

    def timestamp(milliseconds)
      seconds, millis = milliseconds.divmod(1000)
      format("%02d:%02d:%02d.%03d", seconds / 3600, seconds / 60 % 60, seconds % 60, millis)
    end

    def check(condition, message)
      raise InvalidFile, message unless condition
    end
  end
end
