require "digest"

module Minutes
  # Proves where an excerpt occurs, not that it supports the model's claims.
  # Only retained extraction pages can supply a location; current document rows
  # and model-provided page numbers/URLs never participate in this check.
  class LocateEvidence
    RULE_VERSION = "minutes_excerpt_v1"

    def initialize(stage)
      @stage = stage
      @version = stage.meeting_document_text_version
      @source_error = if @version.nil?
        "unretained_source"
      elsif @version.extracted_text != stage.source_text || stage.input_manifest.dig("source", "text_version_id") != @version.id
        "source_mismatch"
      end
      build_index unless @source_error
    end

    def call(data)
      { "rule_version" => RULE_VERSION, "source_key" => @stage.source_key, "text_version_id" => @version&.id,
        "motions" => data.fetch("motions").each_with_index.map { |motion, index| locate(motion["source_excerpt"], index + 1) } }
    end

    private

    def build_index
      @text = +""
      @positions = []
      @pages = @version.pages.index_by { |page| page.fetch("page_number") }
      @pages.each do |number, page|
        page.fetch("cleaned_text").to_enum(:scan, /\S+/).each do |word|
          start = Regexp.last_match.begin(0)
          unless @text.empty?
            @text << " "
            @positions << nil
          end
          word.each_char.with_index do |char, offset|
            @text << char
            @positions << [ number, start + offset ]
          end
        end
      end
    end

    def locate(excerpt, sequence)
      result = { "sequence" => sequence, "status" => "unresolved", "locations" => [] }
      return result.merge("reason" => @source_error) if @source_error
      return result.merge("reason" => "missing_excerpt") if excerpt.nil?
      return result.merge("reason" => "invalid_excerpt") unless excerpt.is_a?(String)

      excerpt = excerpt.scan(/\S+/).join(" ")
      return result.merge("reason" => "missing_excerpt") if excerpt.empty?
      result["excerpt"] = excerpt
      start = @text.index(excerpt)
      return result.merge("reason" => "excerpt_not_found") unless start
      return result.merge("reason" => "ambiguous_excerpt") if @text.index(excerpt, start + 1)

      locations = @positions.slice(start, excerpt.length).compact.group_by(&:first).map do |number, positions|
        { "kind" => "pdf_passage", "page_number" => number, "start_char" => positions.first.last,
          "end_char" => positions.last.last + 1, "page_text_sha256" => Digest::SHA256.hexdigest(@pages.fetch(number).fetch("cleaned_text")) }
      end
      result.merge("status" => "located", "locations" => locations)
    end
  end
end
