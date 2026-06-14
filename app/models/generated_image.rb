class GeneratedImage < ApplicationRecord
  STATUSES = %w[pending processing ready failed superseded disabled].freeze
  PURPOSES = %w[feature og feature_and_og].freeze

  belongs_to :imageable, polymorphic: true
  belongs_to :source_summary, class_name: "MeetingSummary", optional: true
  belongs_to :source_briefing, class_name: "TopicBriefing", optional: true
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_one_attached :file

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :purpose, presence: true, inclusion: { in: PURPOSES }
  validates :retry_count, numericality: { greater_than_or_equal_to: 0 }
  validate :source_provenance_matches_imageable
  validate :source_provenance_is_mutually_exclusive

  scope :ready, -> { where(status: "ready") }
  scope :newest, -> { order(Arel.sql("generated_at DESC NULLS LAST"), created_at: :desc) }
  scope :usable_for, ->(surface) {
    surface = surface.to_s
    purposes = surface == "og" ? %w[og feature_and_og] : %w[feature feature_and_og]
    ready.where(purpose: purposes).newest
  }

  def ready?
    status == "ready"
  end

  def failed?
    status == "failed"
  end

  def retry_available?
    failed? && retry_count <= 1
  end

  private

  def source_provenance_is_mutually_exclusive
    return unless source_summary.present? && source_briefing.present?

    errors.add(:base, "cannot have both source_summary and source_briefing")
  end

  def source_provenance_matches_imageable
    if source_summary.present? && imageable != source_summary.meeting
      errors.add(:imageable, "must match source_summary.meeting")
    end

    if source_briefing.present? && imageable != source_briefing.topic
      errors.add(:imageable, "must match source_briefing.topic")
    end
  end
end
