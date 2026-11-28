class CouncilElectionCandidateList < ApplicationRecord
  normalizes :source_url, with: ->(url) { url.strip.presence }

  validates :election_on, :names, presence: true
  validate :public_source_url, if: -> { source_url.present? }

  private

  def public_source_url
    uri = URI.parse(source_url)
    return if uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?

    errors.add(:source_url, "must be a public HTTP or HTTPS link")
  rescue URI::InvalidURIError
    errors.add(:source_url, "must be a valid public link")
  end
end
