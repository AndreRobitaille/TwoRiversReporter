module Campaigns
  # Historical source leads are distinct from source material accepted by an editor.
  class ElectionBackfill
    EDITIONS = YAML.safe_load_file(Rails.root.join("config/election_backfill.yml")).freeze

    def self.for(year)
      EDITIONS[year.to_s]
    end

    def self.import_questionnaire!(edition, lead, html)
      article = QuestionnaireArticle.new(edition, lead).read(html)
      source = CampaignSource.find_or_create_by!(source_url: lead.fetch("url")) do |source|
        source.assign_attributes(lead.slice("title", "publisher", "published_on"))
        source.assign_attributes(election_on: edition.fetch("election_on"), coverage: lead["section"] ? "selected_excerpts" : "full_article",
          coverage_notes: lead["section"], body: article.body, questionnaire_portraits: article.portraits)
      end
      if article.portraits.present?
        source.with_lock do
          source.add_article_portraits(article.portraits)
          source.save! if source.changed?
        end
      end
      source
    end

    # Match standalone headings so a candidate can mention another race in an answer.
    def self.council_excerpt(body, lead)
      return unless lead && lead["end_heading"]

      lines = body.to_s.lines
      headings = lines.map { |line| line.squish.delete_suffix(":").downcase }
      first = headings.index(lead["start_heading"]&.downcase)
      last = headings.index(lead.fetch("end_heading").downcase)
      return unless first || last

      lines[(first ? first + 1 : 0)...last].join
    end

    def self.catalog_article(record)
      edition = self.for(record.election_on.year)
      return unless edition && edition.fetch("election_on") == record.election_on.iso8601

      edition.fetch("sources").each_value.find { |item| item["kind"] == "article" && item["url"] == record.source_url }
    end

    def self.htr?(record)
      record.publisher.to_s.match?(/\bHerald Times Reporter\b/i)
    end

    def self.caption_path(lead)
      return unless lead && lead["kind"] == "forum"
      id = lead["url"].to_s[%r{\Ahttps://www\.youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})\z}, 1]
      return unless id

      path = Rails.root.join("storage", "election-captions", "#{id}.vtt")
      path if path.file?
    end

    def self.lead(year, key, kind:)
      lead = self.for(year)&.dig("sources", key)
      lead if lead && lead["kind"] == kind
    end
  end
end
