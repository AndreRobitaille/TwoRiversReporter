module CouncilProfiles
  # Search the entire service window before selecting short, independently
  # cited passages for each position. Word overlap never assigns a grade.
  class PromiseMinutes
    COMMON = (Campaigns::ComparisonTargets::COMMON.to_a + %w[
      said wanted supported favored proposed councilmember suggested people sought pursue
      possible spoke ideas work should there those about their whether member document
    ]).join(" ").freeze
    WINDOW = 95

    def initialize(member, range)
      @member, @range = member, range
    end

    def for_position(item)
      prepare unless @passages
      statements = Array(item[:statements])
      topics = statements.flat_map { |s| s.related_topics.map(&:canonical_name) }.uniq
      words = statements.filter_map { |s| s.data["supporting_quote"] }.join(" ")
      heading, description, hints, topic_words, campaign_words = Campaigns::ComparisonTargets.lexemes([
        item.fetch(:heading), item.fetch(:description), Array(item[:search_terms]).join(" "), topics.join(" "), words
      ]).map { |terms| terms - @common }
      primary = heading | hints | topic_words
      primary = description if primary.empty?
      query = primary | description
      limit = item.fetch(:reports, []).any? ? 1 : 2
      candidates = @passages.filter_map do |passage|
        terms = passage.fetch(:terms) & query
        next if terms.empty? || (terms & primary).empty?
        weights = terms.map { |word| @weights.fetch(word) * (primary.include?(word) ? 1.5 : 1) }.sort.reverse
        # A common word such as "park" or "business" is insufficient. A rare
        # term can identify a specific mechanism such as an incubator.
        next if weights.one? && weights.first < 8
        strength = weights.first(5).sum + (passage[:terms] & campaign_words).size.clamp(0, 4)
        strength *= 1.7 if passage[:personal]
        strength *= 1.2 if passage[:result]
        [ strength, passage ]
      end
      candidates.sort_by { |score, p| [ -score, -p[:date].jd, p[:url], p[:text] ] }
        .uniq { |_score, p| p[:url] }.first(limit).map do |_score, p|
          { kind: "Minutes excerpt", text: p[:text], dates: [ p[:date] ], position: item[:heading],
            identity: p[:identity], sources: [ { label: "#{p[:date]} · #{p[:body]}", url: p[:url] } ] }
        end
    end

    private

    def prepare
      @passages = []
      frequency = Hash.new(0)
      family = @member.name.split.last
      others = Member.where("name ILIKE ?", "% #{Member.sanitize_sql_like(family)}").where.not(id: @member.id).pluck(:name)
      @common = Campaigns::ComparisonTargets.lexemes([ "#{COMMON} #{@member.name}" ]).first
      documents = MeetingDocument.where(document_type: %w[minutes_pdf minutes_html]).joins(:meeting)
        .where(meetings: { starts_at: @range }).where.not(source_url: [ nil, "" ]).where.not(extracted_text: [ nil, "" ])
        .where("meetings.status IS DISTINCT FROM 'cancelled' AND meetings.body_name !~* ?", '\m(cancelled|canceled|no quorum)\M')
        .order(Arel.sql("meetings.starts_at, source_url, latest_text_version_id DESC NULLS LAST, length(extracted_text) DESC, meeting_documents.id"))
        .pluck(:source_url, "meetings.starts_at", "meetings.body_name", :extracted_text)
        .uniq { |url, _time, _body, _text| url }
      documents.each do |url, time, body, text|
        identity = [ @member.name ]
        if text.match?(/\b#{Regexp.escape(@member.name)}\b/i) && others.none? { |name| text.match?(/\b#{Regexp.escape(name)}\b/i) }
          identity << family
        end
        # Overlap preserves decisions crossing page breaks in flattened OCR.
        words = text.split
        spans = (0...words.size).step(WINDOW - 25).map { |offset| words.slice(offset, WINDOW).join(" ") }
        stems = Campaigns::ComparisonTargets.lexemes(spans)
        stems.reduce(Set.new, :|).each { |term| frequency[term] += 1 }
        spans.zip(stems).each do |span, terms|
          next unless span.match?(/\b(?:adopted?|approv(?:al|ed)|awarded?|granted|contract|authorize[ds]?|motion|moved|vot(?:ed|ing)|funded|opened|closed|purchased|amended|withdrew|withdrawn|reported|secured|completed|recommended|asked|requested)\b/i)
          @passages << { text: span, terms: terms, url: url, body: body, date: time.in_time_zone.to_date, identity: identity,
            personal: PromiseFollowThrough.named_action?(span, identity),
            result: span.match?(/\$[\d,]+|\b(?:adopted|awarded|completed|closed|opened|executed|funded|purchased|enrolled|attended)\b/i) }
        end
      end
      @weights = frequency.transform_values { |df| 1 + Math.log((1.0 + documents.size) / (1 + df)) }
    end
  end
end
