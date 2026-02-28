class MeetingAttendance < ApplicationRecord
  belongs_to :meeting
  belongs_to :member

  STATUSES = %w[present absent excused].freeze
  ATTENDEE_TYPES = %w[voting_member non_voting_staff guest].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :attendee_type, presence: true, inclusion: { in: ATTENDEE_TYPES }
  validates :member_id, uniqueness: { scope: :meeting_id }

  scope :present, -> { where(status: "present") }
  scope :voting_members, -> { where(attendee_type: "voting_member") }
  scope :for_committee, ->(committee_id) {
    joins(:meeting).where(meetings: { committee_id: committee_id })
  }
end
