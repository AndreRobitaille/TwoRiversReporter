module Campaigns
  # Historical source leads are distinct from source material accepted by an editor.
  class ElectionBackfill
    EDITIONS = YAML.safe_load_file(Rails.root.join("config/election_backfill.yml")).freeze

    def self.election_on(year)
      date = EDITIONS.dig(year.to_s, "election_on")
      date ? Date.iso8601(date) : ResidentContent::CouncilElection.for_year(year)&.election_on
    end

    def self.for(year)
      historical = EDITIONS[year.to_s]
      date = election_on(year)
      return unless date

      discoveries = ElectionArticleLead.where(election_on: date).order(:id).to_a
      forums = ElectionForum.where(election_on: date).order(:held_on, :id).to_a
      return historical if discoveries.empty? && forums.empty?

      edition = historical || { "election_on" => date.iso8601,
        "candidates" => ResidentContent::CouncilElection.for_year(year).candidates.keys, "sources" => {} }
      sources = edition.fetch("sources").dup
      discoveries.each do |discovery|
        next if sources.values.any? { |s| [ s["url"], s["original_url"] ].include?(discovery.source_url) }
        sources["article_#{discovery.id}"] = discovery.questionnaire
      end
      listed_keys = sources.keys.index_by { |key| sources.fetch(key).fetch("url") }
      forums.each do |forum|
        forum.recording_leads.each do |key, lead|
          source_key = listed_keys.fetch(lead.fetch("url"), key)
          sources[source_key] = lead.merge(sources.fetch(source_key, {}))
        end
      end
      edition.merge("sources" => sources, "announced_forums" => forums.select { |forum| forum.recordings.empty? })
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
