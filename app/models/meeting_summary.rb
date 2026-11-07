class MeetingSummary < ApplicationRecord
  SUMMARY_TYPES = %w[minutes_recap transcript_recap packet_analysis agenda_preview].freeze

  belongs_to :meeting

  scope :published, -> { where(evidence_withdrawn_at: nil) }

  def published?
    evidence_withdrawn_at.nil?
  end

  validates :summary_type, presence: true, inclusion: { in: SUMMARY_TYPES }
end
