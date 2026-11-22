class KnowledgeSource < ApplicationRecord
  ORIGINS = %w[manual extracted pattern].freeze
  STATUSES = %w[proposed approved blocked].freeze

  has_many :knowledge_chunks, dependent: :destroy
  has_many :knowledge_source_topics, dependent: :destroy
  has_many :topics, through: :knowledge_source_topics
  has_one_attached :file
  belongs_to :meeting, optional: true
  belongs_to :source_summary, class_name: "MeetingSummary", optional: true

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
  scope :available, -> { where(evidence_withdrawn_at: nil) }
  scope :retrievable, -> { available.approved.where(active: true) }

  after_save :ingest_later, if: -> { saved_change_to_body? || attachment_changes["file"].present? }

  def ingest_later
    return unless available?

    IngestKnowledgeSourceJob.perform_later(id)
  end

  def available?
    evidence_withdrawn_at.nil?
  end
end
