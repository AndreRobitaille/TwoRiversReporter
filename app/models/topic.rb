class Topic < ApplicationRecord
  has_many :agenda_item_topics, dependent: :destroy
  has_many :agenda_items, through: :agenda_item_topics
  has_many :topic_aliases, dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :status, presence: true, inclusion: { in: %w[proposed approved blocked] }
  validates :importance, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }, allow_nil: true

  scope :approved, -> { where(status: "approved") }
  scope :proposed, -> { where(status: "proposed") }
  scope :blocked, -> { where(status: "blocked") }
  scope :pinned, -> { where(pinned: true) }
  scope :publicly_visible, -> { where(status: "approved").or(where(pinned: true)) }
  scope :similar_to, ->(query, threshold = 0.7) {
    where("similarity(name, ?) > ?", query, threshold)
      .order(Arel.sql("similarity(name, '#{ActiveRecord::Base.sanitize_sql(query)}') DESC"))
  }

  before_validation :normalize_name

  def self.normalize_name(name)
    return nil if name.blank?
    name.strip.downcase.gsub(/[[:punct:]]/, "").squish
  end

  private

  def normalize_name
    self.name = self.class.normalize_name(name)
  end
end
