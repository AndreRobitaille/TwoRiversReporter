class CouncilElectionResult < ApplicationRecord
  validates :election_on, :confirmed_on, :candidate_names, :winner_names, presence: true
  validates :source_url, format: { with: %r{\Ahttps?://[^/\s]+/\S+\z} }
  validate :complete_result

  def self.confirm!(election_on:, confirmed_on:, source_url:, winner_names:)
    record = find_or_initialize_by(election_on: election_on)
    field = Campaigns::ElectionBackfill.candidates_on(election_on)
    record.update!(candidate_names: field.presence || record.candidate_names, winner_names: winner_names,
      confirmed_on: confirmed_on, source_url: source_url)
    record
  end

  def self.confirmed_by(day)
    historical = Campaigns::ElectionBackfill::EDITIONS.values.filter_map do |edition|
      next unless edition["canvassed_on"]

      new(election_on: edition.fetch("election_on"), confirmed_on: edition.fetch("canvassed_on"),
        candidate_names: edition.fetch("candidates"), winner_names: edition.fetch("term_members"), source_url: edition.fetch("canvass_source"))
    end
    historical.select { |result| result.confirmed_on <= day }.index_by(&:election_on)
      .merge(where(confirmed_on: ..day).index_by(&:election_on))
  end

  private

  def complete_result
    if election_on && confirmed_on && confirmed_on < election_on
      errors.add(:confirmed_on, "must be on or after Election Day")
    end
    winners = Array(winner_names)
    unless winners.size == 3 && winners.uniq.size == 3 && winners.all?(&:present?) && (winners - Array(candidate_names)).empty?
      errors.add(:winner_names, "must name the three elected candidates from this Council field")
    end
  end
end
