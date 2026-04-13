class MeetingSummary < ApplicationRecord
  SUMMARY_TYPES = %w[minutes_recap transcript_recap packet_analysis].freeze

  belongs_to :meeting

  validates :summary_type, presence: true, inclusion: { in: SUMMARY_TYPES }
end
