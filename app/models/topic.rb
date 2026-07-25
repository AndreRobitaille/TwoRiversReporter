class Topic < ApplicationRecord
  has_many :agenda_item_topics, dependent: :destroy
  has_many :agenda_items, through: :agenda_item_topics
  has_many :knowledge_source_topics, dependent: :destroy
  has_many :knowledge_sources, through: :knowledge_source_topics
  has_many :topic_aliases, dependent: :destroy
  has_many :topic_appearances, dependent: :destroy
  has_many :topic_status_events, dependent: :destroy
  has_many :topic_review_events, dependent: :destroy
  has_many :topic_summaries, dependent: :destroy
  has_many :generated_images, as: :imageable, dependent: :destroy
  has_one :topic_briefing, dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :status, presence: true, inclusion: { in: %w[proposed approved blocked] }
  validates :review_status, inclusion: { in: %w[proposed approved blocked] }, allow_nil: true
  validates :lifecycle_status, inclusion: { in: %w[active dormant resolved recurring] }, allow_nil: true
  validates :reuse_strategy, inclusion: { in: %w[canonical unsafe_for_auto_reuse] }
  validates :canonical_name, uniqueness: true, allow_nil: true
  validates :slug, uniqueness: true, allow_nil: true

  validates :importance, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }, allow_nil: true
  validates :resident_impact_score, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 1,
    less_than_or_equal_to: 5
  }, allow_nil: true

  store_accessor :resident_reported_context, :source_type, :source_notes, :added_by, :added_at

  scope :approved, -> { where(status: "approved") }
  scope :proposed, -> { where(status: "proposed") }
  scope :blocked, -> { where(status: "blocked") }
  scope :pinned, -> { where(pinned: true) }
  scope :publicly_visible, -> { where(status: "approved") }
  scope :reusable, -> { approved.where(reuse_strategy: "canonical") }
  scope :unsafe_for_auto_reuse, -> { where(reuse_strategy: "unsafe_for_auto_reuse") }

  scope :active, -> { where(lifecycle_status: "active") }
  scope :dormant, -> { where(lifecycle_status: "dormant") }
  scope :resolved, -> { where(lifecycle_status: "resolved") }
  scope :recurring, -> { where(lifecycle_status: "recurring") }

  scope :review_proposed, -> { where(review_status: "proposed") }
  scope :review_approved, -> { where(review_status: "approved") }
  scope :review_blocked, -> { where(review_status: "blocked") }

  # Columns that describe a topic rather than narrate it: the topic's own
  # name, its canonical form, its scope description, and its aliases. All of
  # these are visible to every visitor on a topic card, so matching against
  # them tells an anonymous searcher nothing the page would not already show.
  PUBLIC_SEARCH_COLUMNS = [
    "LOWER(topics.name)",
    "LOWER(topics.canonical_name)",
    "LOWER(topics.description)",
    "LOWER(topic_aliases.name)"
  ].freeze

  # AI-generated narrative. Gated visitors see at most the first 90 characters
  # of this on a card, and only for the two topics the anonymous cap admits.
  BRIEFING_SEARCH_COLUMN = "LOWER(topic_briefings.headline)".freeze

  # Full-text search, including generated briefing headlines. Safe only for
  # signed-in members, open mode, and admin surfaces.
  scope :search_by_text, ->(query) { text_search(query, briefing_headlines: true) }

  # Public-record search: name / canonical name / description / aliases, never
  # `topic_briefings.headline`. Matching on the headline makes the *shape* of
  # the results list a function of withheld text — `?q=<tail of a withheld
  # headline>` returns a card, `?q=<that plus one character>` returns nothing,
  # which is a one-character-resolution confirm oracle over content the gate
  # exists to withhold. The response body carries no withheld bytes either
  # way, so the canary sweep is structurally blind to it. Use this scope for
  # anonymous visitors in gated mode.
  scope :search_by_public_text, ->(query) { text_search(query, briefing_headlines: false) }

  # Shared body of the two search scopes above. Kept as one method so the two
  # cannot drift apart in anything except the briefing-headline term.
  def self.text_search(query, briefing_headlines:)
    return none if query.blank?
    normalized_query = normalize_name(query)
    return none if normalized_query.blank?

    term = "%#{sanitize_sql_like(normalized_query)}%"
    columns = PUBLIC_SEARCH_COLUMNS.dup
    columns << BRIEFING_SEARCH_COLUMN if briefing_headlines

    relation = left_outer_joins(:topic_aliases)
    relation = relation.left_outer_joins(:topic_briefing) if briefing_headlines
    relation
      .where(columns.map { |column| "#{column} LIKE :q" }.join(" OR "), q: term)
      .distinct
      .order(:name)
  end

  scope :similar_to, ->(query, threshold = 0.7) {
    where("similarity(name, ?) > ?", query, threshold)
      .order(Arel.sql("similarity(name, '#{ActiveRecord::Base.sanitize_sql(query)}') DESC"))
  }

  before_validation :maintain_derived_fields

  RESIDENT_IMPACT_OVERRIDE_WINDOW = 180.days

  def self.normalize_name(name)
    return nil if name.blank?
    name.strip.downcase.gsub(/[[:punct:]]/, "").squish
  end

  def approved?
    status == "approved"
  end

  def resident_impact_admin_locked?
    resident_impact_overridden_at.present? &&
      resident_impact_overridden_at > RESIDENT_IMPACT_OVERRIDE_WINDOW.ago
  end

  def update_resident_impact_from_ai(score)
    return if resident_impact_admin_locked?

    update(resident_impact_score: score)
  end

  def current_generated_image(surface = :feature)
    generated_images.usable_for(surface).first
  end

  private

  def maintain_derived_fields
    self.name = self.class.normalize_name(name)
    self.reuse_strategy = "canonical" if reuse_strategy.blank?

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
