module Campaigns
  # Work from the positions a resident sees. Retrieval suggests comparisons;
  # only the separately checked minutes or personal-action record can support one.
  class ComparisonTargets
    COMMON = %w[about across after annual before city council consider create develop development
      expand could form from give government help high improve keep local make manager more position project projects
      public replace residents resources role should staff stated support through using with would].to_set.freeze

    def initialize(statements)
      ActiveRecord::Associations::Preloader.new(records: statements, associations: :related_topics).call
      @targets = ResidentContent::CampaignPlatform.by_election(statements).values.flat_map do |platform|
        items = platform.items.map { |item| platform_target(item) }
        legacy = platform.unreviewed.reject { |row| row.data["kind"] == "retrospective_claim" }
        items + legacy.map { |row| { statements: [ row ], topics: row.related_topics.map(&:id), phrases: [] } }
      end
    end

    # PostgreSQL's English dictionary matches a campaign's wording (e.g.
    # "kayaking" or "houses") to inflections used in the official record.
    def self.lexemes(texts)
      texts.each_slice(100).flat_map do |batch|
        sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, batch.to_json ])
          SELECT to_json(tsvector_to_array(to_tsvector('english', value)))::text
          FROM jsonb_array_elements_text(?::jsonb) WITH ORDINALITY ORDER BY ordinality
        SQL
        ApplicationRecord.connection.select_values(sql).map { |json| JSON.parse(json).to_set }
      end
    end

    def matches(topic_ids, subject, date, meeting:, agenda_item:, action: nil, recap_terms: nil)
      prepare_recap_terms if recap_terms && !@recap_terms_ready
      text = " #{words(subject).join(" ")} "
      docket = agenda_item&.title.to_s[/\A\d{2}-\d{3}\b/]
      @targets.flat_map do |target|
        # The same dated decision may be relevant to one position and unrelated to another.
        next [] if docket && target.fetch(:handled_records, []).any? do |source|
          source.fetch("docket") == docket && meeting.meeting_documents.exists?(source_url: source.fetch("document_url")) &&
            !agenda_item.motions.many?
        end
        review = target[:reviewed_action]
        editorial = review && action && review.fetch("quote") == action.dig(:evidence, "quote") &&
          review.fetch("minutes_url") == action.dig(:citation, :source_url)
        shares_topic = target[:topics].intersect?(topic_ids)
        matches_wording = recap_terms && (target[:primary_concepts]&.intersect?(recap_terms) ||
          (target[:concepts] && (target[:concepts] & recap_terms).size >= 2) ||
          target.fetch(:topic_names, []).any? { |name| text.include?(name) })
        next [] unless editorial || shares_topic || matches_wording || target[:phrases].any? { |phrase| text.include?(phrase) }
        mentions = target[:statements].select do |row|
          source = row.campaign_source_version
          (source.published_on || source.election_on) <= date
        end
        mentions.map do |row|
          { statement: row, focus: target[:focus], platform_test: target[:platform_test], comparison_group: [ mentions.first.id, target[:focus] ],
            reuse_topic_match: target[:comparison_topic] && shares_topic, prior_review_terms: target[:prior_review_terms],
            editorial_reason: editorial && row == mentions.first ? review.fetch("reason") : nil }
        end
      end.uniq { |candidate| [ candidate[:statement].id, candidate[:focus] ] }
    end

    def empty?
      @targets.empty?
    end

    def topic_ids
      @targets.flat_map { |target| target.fetch(:topics) }.uniq
    end

    private

    def platform_target(item)
      heading = item.fetch(:heading)
      mentions = item.fetch(:statements)
      topics = mentions.flat_map { |row| row.related_topics.map(&:id) }.uniq
      tokens = words(heading)
      if item[:comparison_topic]
        topics = Topic.approved.where(canonical_name: item[:comparison_topic]).ids
      elsif topics.empty?
        # A word specific to one approved topic can recover a missing tag
        # (e.g. "pipes" in the water-main topic's description).
        topics = tokens.reject { |word| common?(word) }.flat_map do |word|
          ids = catalog.fetch(word, [])
          ids.one? ? ids : []
        end.uniq
      end
      phrases = tokens.each_cons(2).filter_map do |a, b|
        " #{a} #{b} " unless common?(a) || common?(b)
      end
      # Common words together can name a precise policy, e.g. "manager form of government".
      phrases.concat(tokens.each_cons(4).map { |phrase| " #{phrase.join(" ")} " })
      phrases.concat(Array(item[:search_terms]).map { |term| " #{words(term).join(" ")} " })
      # An old statement can contain two alternatives. Compare the exact part
      # being shown, and keep its results separate from its sibling's.
      focus = item.slice(:heading, :description).stringify_keys if item[:comparable].empty? || item[:comparison_topic]
      platform_test = item.slice(:heading, :undertaking, :record_test).stringify_keys if item[:record_test]
      { platform_test: platform_test, statements: item[:comparable].presence || [ mentions.first ], topics: topics, phrases: phrases, focus: focus,
        comparison_topic: item[:comparison_topic], prior_review_terms: item[:prior_review_terms], reviewed_action: item[:reviewed_action],
        handled_records: item[:handled_records] || [],
        topic_names: mentions.flat_map(&:related_topics).map { |topic| " #{words(topic.canonical_name).join(" ")} " }.uniq,
        wording: [ item.fetch(:description), mentions.map { |m| m.data["supporting_quote"] }.join(" "),
          [ heading, item.fetch(:description)[/\b(?:such as|for example|including)\s+([^.!?]+)/i, 1] ].compact.join(" ") ] }
    end

    def prepare_recap_terms
      targets = @targets.select { |target| target[:wording] }
      # Look for language shared by the narrower description and the candidate's
      # own words. An aside in a compound forum answer isn't enough.
      common = (COMMON.to_a + %w[people want favor suggest believe think need continue possible include attract
        place address discuss happen encourage year larger things example working]).join(" ")
      terms = self.class.lexemes([ common, *targets.flat_map { |target| target.fetch(:wording) } ])
      excluded = terms.shift
      targets.zip(terms.each_slice(3)) do |target, (description, quote, primary)|
        target[:concepts] = ((description & quote) - excluded).delete_if { |word| word.length < 4 }
        target[:primary_concepts] = target[:concepts] & primary
      end
      @recap_terms_ready = true
    end

    def catalog
      @catalog ||= begin
        index = Hash.new { |hash, word| hash[word] = [] }
        Topic.approved.pluck(:id, :canonical_name, :description).each do |id, name, description|
          text = [ name, description ].join(" ")
          words(text).uniq.each { |word| index[word] << id }
        end
        index
      end
    end

    def common?(word)
      word.length < 4 || COMMON.include?(word)
    end

    def words(text)
      text.to_s.downcase.scan(/[[:alnum:]]+/)
    end
  end
end
