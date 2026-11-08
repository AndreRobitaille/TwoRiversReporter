require "digest"
require "uri"

# Private source intake. Saving text does not extract statements or publish it.
class CampaignSource < ApplicationRecord
  SNAPSHOT_FIELDS = %w[title source_url publisher published_on election_on coverage coverage_notes body].freeze
  COVERAGES = { "full_article" => "Complete article", "selected_excerpts" => "Selected excerpts" }.freeze

  has_many :versions, class_name: "CampaignSourceVersion", dependent: :restrict_with_exception
  attr_accessor :submitted_by

  normalizes :title, :source_url, :publisher, with: ->(value) { value.strip }
  normalizes :body, with: ->(value) { value.gsub(/\r\n?/, "\n").strip }
  normalizes :coverage_notes, with: ->(value) { value.strip.presence }
  validates :title, :source_url, :publisher, :election_on, :body, presence: true
  validates :source_url, uniqueness: true
  validates :coverage, inclusion: { in: COVERAGES.keys }
  validates :body, length: { maximum: 200_000 }
  validate :publisher_url
  after_save :retain_version

  def current_version
    versions.find_by(version_key: version_key)
  end

  private

  def version_key
    Digest::SHA256.hexdigest(JSON.generate([ id, attributes.slice(*SNAPSHOT_FIELDS) ]))
  end

  def retain_version
    # Reload under the save transaction's row lock: partial updates from a stale
    # instance must snapshot the complete persisted article, not its old fields.
    with_lock do
      versions.find_or_create_by!(version_key: version_key) do |version|
        version.assign_attributes(attributes.slice(*SNAPSHOT_FIELDS))
        version.content_sha256 = Digest::SHA256.hexdigest(body)
        version.submitted_by = submitted_by
      end
    end
  end

  def publisher_url
    uri = URI.parse(source_url.to_s)
    unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank?
      errors.add(:source_url, "must be an HTTP or HTTPS publisher link without credentials")
    end
  rescue URI::InvalidURIError
    errors.add(:source_url, "must be a valid publisher link")
  end
end
