module Topics
  # Generated background for an agenda preview, separate from its official source
  # catalog. Capture once before generation and check those exact inputs at save.
  class AgendaBriefingContext
    VERSION = 1
    MIN_TOKEN_OVERLAP = 3
    MIN_IMPACT = 3
    MAX_HITS = 6
    STOPWORDS = Set.new(%w[
      a an the of and or but to for in on at by with from as is be are was were
      been being this that these those it its their our your my me us we they he
      she his her them have has had do does did not no so if then than which who
      whom whose where when why how all any each every some other into out up down
      off over under same own more most less few many such new old
    ]).freeze

    def self.current_manifest(manifest)
      new(nil, receipt: manifest).current_manifest if valid_manifest?(manifest)
    end

    def self.with_current(manifest, topic_ids: [], &block)
      if manifest.nil?
        Topic.transaction do
          lock_topics(topic_ids)
          yield
        end
      elsif valid_manifest?(manifest)
        new(nil, receipt: manifest).with_current(topic_ids: topic_ids, &block)
      end
    end

    def self.lock_topics(*ids)
      Topic.where(id: ids.flatten.compact.uniq).order(:id).lock.load
    end

    def self.valid_manifest?(manifest)
      manifest.is_a?(Hash) && manifest["version"] == VERSION &&
        manifest["agenda_tokens"].is_a?(Array) && manifest["agenda_tokens"].all? { |token| token.is_a?(String) } &&
        manifest["entries"].is_a?(Array) && manifest["entries"].size <= MAX_HITS &&
        manifest["entries"].all? do |item|
          item.is_a?(Hash) && item["topic_id"].is_a?(Integer) && item["briefing_id"].is_a?(Integer) && item["section"].is_a?(String)
        end
    end
    private_class_method :valid_manifest?

    def initialize(agenda_text, receipt: nil)
      if receipt
        @agenda_tokens = Set.new(receipt.fetch("agenda_tokens"))
        @entries = receipt.fetch("entries")
        return
      end
      @agenda_tokens = significant_tokens(agenda_text)
      @entries = if @agenda_tokens.size < MIN_TOKEN_OVERLAP
        []
      else
        eligible_topics.filter_map do |topic|
          overlap = token_overlap(topic)
          [ topic, overlap ] if overlap >= MIN_TOKEN_OVERLAP
        end.sort_by { |topic, overlap| [ -topic.resident_impact_score.to_i, -overlap, topic.id ] }
          .first(MAX_HITS).map { |topic, _| entry(topic) }
      end
    end

    def text
      return "" if @entries.empty?

      <<~TOPIC_CONTEXT.strip
        <topic_briefings>
        The following topics are ongoing civic concerns in Two Rivers that share content words with the agenda text. Use them to ground your analysis where clearly relevant to an agenda item — residents already recognize these issues. These are established context, not outcomes from this meeting. Ignore entries that don't actually line up with any item.

        #{@entries.map { |item| item.fetch("section") }.join("\n\n")}
        </topic_briefings>
      TOPIC_CONTEXT
    end

    def manifest
      { "version" => VERSION, "agenda_tokens" => @agenda_tokens.to_a.sort, "entries" => @entries }
    end

    def current_manifest
      current = eligible_topics.where(id: @entries.map { |item| item.fetch("topic_id") }).filter_map do |topic|
        entry(topic) if token_overlap(topic) >= MIN_TOKEN_OVERLAP
      end.index_by { |item| item.fetch("topic_id") }
      manifest.merge("entries" => @entries.filter_map { |item| current[item.fetch("topic_id")] })
    end

    def current?
      manifest == current_manifest
    end

    def with_current(topic_ids: [])
      # Topic, alias and briefing writers share these locks, including when no
      # summary exists yet. Providers run before this transaction.
      Topic.transaction do
        Topic.uncached do
          self.class.lock_topics(topic_ids, @entries.map { |item| item.fetch("topic_id") })
          yield if current?
        end
      end
    end

    private

    def eligible_topics
      Topic.approved.where("resident_impact_score >= ?", MIN_IMPACT)
        .joins(:published_topic_briefing)
        .where.not(topic_briefings: { editorial_content: [ nil, "" ] })
        .eager_load(:topic_aliases, :published_topic_briefing)
    end

    def entry(topic)
      briefing = topic.published_topic_briefing
      parts = [ "## Known topic: #{topic.name}", "Impact score: #{topic.resident_impact_score}" ]
      parts << "Current state: #{briefing.headline}" if briefing.headline.present?
      parts << "Coming up: #{briefing.upcoming_headline}" if briefing.upcoming_headline.present?
      parts << briefing.editorial_content.to_s.truncate(1200) if briefing.editorial_content.present?
      { "topic_id" => topic.id, "briefing_id" => briefing.id, "section" => parts.join("\n") }
    end

    def token_overlap(topic)
      ([ topic.name ] + topic.topic_aliases.map(&:name)).map do |needle|
        tokens = significant_tokens(needle)
        tokens.size < MIN_TOKEN_OVERLAP ? 0 : (tokens & @agenda_tokens).size
      end.max || 0
    end

    def significant_tokens(text)
      Set.new(text.to_s.downcase.scan(/[a-z]+/).filter_map do |word|
        next if word.length < 3 || STOPWORDS.include?(word)
        word.sub(/s\z/, "")
      end)
    end
  end
end
