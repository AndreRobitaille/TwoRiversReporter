class Topic < ApplicationRecord
  has_many :agenda_item_topics, dependent: :destroy
  has_many :agenda_items, through: :agenda_item_topics
  has_many :topic_aliases, dependent: :destroy
  has_many :topic_appearances, dependent: :destroy
  has_many :topic_status_events, dependent: :destroy
  has_many :topic_review_events, dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :status, presence: true, inclusion: { in: %w[proposed approved blocked] }
  validates :review_status, inclusion: { in: %w[proposed approved blocked] }, allow_nil: true
  validates :lifecycle_status, inclusion: { in: %w[active dormant resolved recurring] }, allow_nil: true
  validates :canonical_name, uniqueness: true, allow_nil: true
  validates :slug, uniqueness: true, allow_nil: true

  validates :importance, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }, allow_nil: true

  scope :approved, -> { where(status: "approved") }
  scope :proposed, -> { where(status: "proposed") }
  scope :blocked, -> { where(status: "blocked") }
  scope :pinned, -> { where(pinned: true) }
  scope :publicly_visible, -> { where(status: "approved").or(where(pinned: true)) }

  scope :active, -> { where(lifecycle_status: "active") }
  scope :dormant, -> { where(lifecycle_status: "dormant") }
  scope :resolved, -> { where(lifecycle_status: "resolved") }
  scope :recurring, -> { where(lifecycle_status: "recurring") }

  scope :review_proposed, -> { where(review_status: "proposed") }
  scope :review_approved, -> { where(review_status: "approved") }
  scope :review_blocked, -> { where(review_status: "blocked") }

  scope :similar_to, ->(query, threshold = 0.7) {
    where("similarity(name, ?) > ?", query, threshold)
      .order(Arel.sql("similarity(name, '#{ActiveRecord::Base.sanitize_sql(query)}') DESC"))
  }

  before_validation :maintain_derived_fields

  def self.normalize_name(name)
    return nil if name.blank?
    name.strip.downcase.gsub(/[[:punct:]]/, "").squish
  end

  private

  def maintain_derived_fields
    self.name = self.class.normalize_name(name)

    if name_changed? || canonical_name.blank?
      self.canonical_name = self.class.normalize_name(name)
    end

    if (canonical_name_changed? || slug.blank?) && canonical_name.present?
      self.slug = canonical_name.parameterize
    end

    if status_changed? || review_status.blank?
       self.review_status ||= status
    end
  end
end
