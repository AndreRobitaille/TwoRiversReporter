class KnowledgeSource < ApplicationRecord
  ORIGINS = %w[manual extracted pattern].freeze
  STATUSES = %w[proposed approved blocked].freeze

  has_many :knowledge_chunks, dependent: :destroy
  has_many :knowledge_source_topics, dependent: :destroy
  has_many :topics, through: :knowledge_source_topics
  has_one_attached :file

  validates :title, presence: true
  validates :source_type, presence: true, inclusion: { in: %w[note pdf] }
  validates :origin, presence: true, inclusion: { in: ORIGINS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :reasoning, presence: true, if: -> { origin.in?(%w[extracted pattern]) }

  scope :approved, -> { where(status: "approved") }
  scope :proposed, -> { where(status: "proposed") }
  scope :blocked, -> { where(status: "blocked") }
  scope :extracted, -> { where(origin: "extracted") }
  scope :pattern_derived, -> { where(origin: "pattern") }
  scope :manual, -> { where(origin: "manual") }

  after_save :ingest_later, if: -> { saved_change_to_body? || attachment_changes["file"].present? }

  def ingest_later
    IngestKnowledgeSourceJob.perform_later(id)
  end
end
