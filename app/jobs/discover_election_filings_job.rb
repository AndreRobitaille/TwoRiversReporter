class DiscoverElectionFilingsJob < ApplicationJob
  queue_as :default

  def perform
    today = Date.current
    edition = ResidentContent::CouncilElection.for_year(today.year)
    return unless edition && today.between?(edition.filing_deadline, edition.election_on - 1)
    return if edition.candidates.any?

    watch = ElectionFilingWatch.create_or_find_by!(election_on: edition.election_on)
    return if watch.stopped?

    articles = Campaigns::FilingArticleDiscovery.find(from: [ edition.filing_deadline, today - 7 ].max, through: today)
    ([ watch.article_url ] + articles.map(&:url)).compact.uniq.each do |url|
      break if review_or_publish(watch, edition, url)
    end
  end

  private

  def review_or_publish(watch, edition, url)
    names = read_names(url)
    watch.with_lock do
      return true if watch.stopped? || CouncilElectionCandidateList.exists?(election_on: edition.election_on)
      watch.update!(article_url: url) unless watch.article_url?
      return false unless names

      normalized = edition.normalize_candidate_names(names.join("\n"))
      return false unless normalized.size == names.size

      CouncilElectionCandidateList.create_or_find_by!(election_on: edition.election_on) do |list|
        list.names = normalized
        list.source_url = url
      end
      true
    end
  end

  def read_names(url)
    Campaigns::FilingCandidateReader.names(Campaigns::PublisherHttp.fetch(url))
  rescue Campaigns::PublisherHttp::Unavailable => error
    Rails.logger.info("Council filing story needs editor review: #{error.message}")
    nil
  end
end
