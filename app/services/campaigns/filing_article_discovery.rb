module Campaigns
  class FilingArticleDiscovery
    SEEHAFER_INDEX = "https://www.seehafernews.com/wp-json/wp/v2/posts"
    HTR_INDEX = HtrQuestionnaireDiscovery::NEWS_SITEMAP
    PUBLISHER_STORY = %r{\Ahttps://(?:www\.seehafernews\.com/|www\.htrnews\.com/story/news/(?:[a-z-]+/)*)(\d{4}/\d\d/\d\d)/([a-z0-9-]+)(?:/\d+)?/?\z}
    Article = Data.define(:url, :published_on)

    def self.find(from:, through:)
      params = { search: "two rivers", after: "#{from}T00:00:00", before: "#{through}T23:59:59",
        per_page: 100, _fields: "link,title,date" }
      indexes = { seehafer: "#{SEEHAFER_INDEX}?#{URI.encode_www_form(params)}", htr: HTR_INDEX }
      indexes.flat_map do |publisher, index|
        body = PublisherHttp.fetch(index)
        stories = publisher == :seehafer ? seehafer_stories(body) : htr_stories(body)
        stories.filter_map { |url, title| article(url, title, from..through) }
      rescue PublisherHttp::Unavailable, JSON::ParserError, Nokogiri::XML::SyntaxError => error
        Rails.logger.info("Council filing search at #{publisher}: #{error.message}")
        []
      end.uniq(&:url).sort_by(&:published_on)
    end

    def self.seehafer_stories(body)
      rows = JSON.parse(body)
      return [] unless rows.is_a?(Array)

      rows.map { |row| [ row["link"], row.dig("title", "rendered") ] }
    end

    def self.htr_stories(body)
      doc = Nokogiri::XML(body) { |config| config.strict.nonet }
      doc.xpath("//*[local-name()='url']").map do |entry|
        [ entry.at_xpath("./*[local-name()='loc']")&.text, entry.at_xpath(".//*[local-name()='title']")&.text ]
      end
    end

    def self.article(url, title, dates)
      match = PUBLISHER_STORY.match(url.to_s)
      return unless match

      date = Date.strptime(match[1], "%Y/%m/%d")
      headline = "#{title} #{match[2].tr('-', ' ')}"
      return unless dates.cover?(date) && headline.match?(/\b(?:Two Rivers|Manitowoc County)\b/i)
      return unless headline.match?(/\b(?:fil(?:e[ds]?|ings?)|nomination|paperwork|ballots?|(?:races?|fields?) (?:is |are )?set|who(?:'s| is) running)\b/i)
      return if headline.match?(/\b(?:forums?|questionnaires?|results?|winners?)\b/i)

      Article.new(url, date)
    rescue Date::Error
      nil
    end

    private_class_method :seehafer_stories, :htr_stories, :article
  end
end
