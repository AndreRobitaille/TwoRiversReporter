class Redirect < ApplicationRecord
  SUPPORTED_STATUS_CODES = [ 301, 302, 307, 308 ].freeze
  CACHE_KEY = "redirects/lookup_map".freeze

  validates :source_path, presence: true, uniqueness: { case_sensitive: true }
  validates :destination, presence: true
  validates :status_code, inclusion: { in: SUPPORTED_STATUS_CODES }
  validate :destination_differs_from_source

  before_validation :normalize_source_path
  before_validation :normalize_destination

  after_commit :clear_lookup_cache

  # Returns { destination:, status_code:, id: } for a request path, or nil.
  # Backed by a single cached hash of every redirect, keyed by normalized source_path.
  def self.lookup(path)
    lookup_map[normalize_path(path)]
  end

  def self.lookup_map
    Rails.cache.fetch(CACHE_KEY) do
      all.each_with_object({}) do |redirect, map|
        map[redirect.source_path] = {
          id: redirect.id,
          destination: redirect.destination,
          status_code: redirect.status_code
        }
      end
    end
  end

  # Idempotently create or re-point a redirect for a given source path.
  def self.upsert_redirect(source_path:, destination:, status_code: 301)
    normalized_source = normalize_path(source_path)
    record = find_or_initialize_by(source_path: normalized_source)
    record.destination = destination
    record.status_code = status_code
    record.save!
    record
  end

  def self.normalize_path(value)
    path = value.to_s.strip
    path = path.split(/[?#]/, 2).first.to_s
    path = "/#{path}" unless path.start_with?("/")
    path = path.chomp("/") if path.length > 1
    path
  end

  private

  def normalize_source_path
    return if source_path.blank?

    self.source_path = self.class.normalize_path(source_path)
  end

  def normalize_destination
    value = destination.to_s.strip
    return if value.blank?

    unless value.match?(%r{\A[a-z][a-z0-9+.-]*://}i) || value.start_with?("/")
      value = "/#{value}"
    end
    self.destination = value
  end

  def destination_differs_from_source
    return if source_path.blank? || destination.blank?

    if self.class.normalize_path(destination) == source_path
      errors.add(:destination, "must differ from the source path")
    end
  end

  def clear_lookup_cache
    Rails.cache.delete(CACHE_KEY)
  end
end
