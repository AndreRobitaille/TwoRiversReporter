module Campaigns
  class LatestPortrait
    Photo = Data.define(:image_url, :source_url, :publisher, :date)

    def self.for(names)
      source = CampaignSource.where("jsonb_exists_any(questionnaire_portraits, ARRAY[:names]::text[])", names:)
        .order(Arel.sql("COALESCE(published_on, date_trunc('year', election_on)::date) DESC, id DESC")).first
      if source
        url = source.questionnaire_portraits.values_at(*names).compact.first
        saved = Photo.new(url, source.source_url, source.publisher, source.published_on || source.election_on.beginning_of_year)
      end
      # Prefer the saved article over the bundled reference on the same date.
      [ saved, *catalog.values_at(*names) ].compact.max_by(&:date)
    end

    def self.catalog
      @catalog ||= ElectionBackfill::EDITIONS.values.each_with_object({}) do |edition, photos|
        edition.fetch("sources").each_value do |article|
          article.fetch("portraits", {}).each do |name, url|
            photo = Photo.new(url, article.fetch("url"), article.fetch("publisher"), Date.iso8601(article.fetch("published_on")))
            photos[name] = photo unless photos[name] && photos[name].date >= photo.date
          end
        end
      end
    end
  end
end
