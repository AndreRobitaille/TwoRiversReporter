class DiscoverHtrQuestionnairesJob < ApplicationJob
  queue_as :default
  retry_on Campaigns::HtrQuestionnaireDiscovery::Unavailable, wait: 30.minutes, attempts: 2

  def perform(year = nil)
    date = Campaigns::ElectionBackfill.election_on(year || Date.current.year)
    return unless date
    return if year.nil? && !Date.current.between?(Date.new(date.year, 3, 1), date)

    Campaigns::HtrQuestionnaireDiscovery.find(date).each do |article|
      ElectionArticleLead.find_or_create_by!(source_url: article.url) do |record|
        record.assign_attributes(election_on: date, published_on: article.published_on)
      end
    end
    edition = Campaigns::ElectionBackfill.for(date.year)
    ElectionArticleLead.where(election_on: date).find_each { |discovery| import(discovery, edition) }
  end

  private

  def import(discovery, edition)
    lead = edition.fetch("sources").values.find { |s| [ s["url"], s["original_url"] ].include?(discovery.source_url) }
    url = lead.fetch("url")
    return if CampaignSource.exists?(source_url: url)

    html = Campaigns::HtrQuestionnaireDiscovery.fetch(url)
    discovery.with_lock do
      Campaigns::ElectionBackfill.import_questionnaire!(edition, lead, html) unless CampaignSource.exists?(source_url: url)
    end
  rescue Campaigns::HtrQuestionnaireDiscovery::Unavailable, ArgumentError => error
    # The lead is already on the election desk for the editor's permitted copy.
    Rails.logger.info("HTR questionnaire for #{discovery.election_on} needs editor intake: #{error.message}")
  end
end
