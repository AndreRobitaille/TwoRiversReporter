# Accepted service dates, separate from current roster titles. A missing end
# records an unknown end, not proof of uninterrupted service through today.
class CouncilServicePeriod < ApplicationRecord
  belongs_to :member
  belongs_to :start_source_version, class_name: "MeetingDocumentVersion"
  belongs_to :end_source_version, class_name: "MeetingDocumentVersion", optional: true

  validates :period_key, presence: true, uniqueness: { scope: :member_id },
    format: { with: /\A[a-z0-9][a-z0-9_-]*\z/ }
  validates :started_on, presence: true
  validates :start_page, numericality: { only_integer: true, greater_than: 0 }
  validates :end_page, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :end_has_date_and_source

  scope :newest_first, -> { order(started_on: :desc, id: :desc) }

  # One checked source can establish dates for multiple people. Callers resolve
  # existing Member IDs and validate the source assertions before this boundary.
  # Keep period_key stable when correcting dates; unchanged inputs write nothing.
  def self.record_starts!(period_key:, source_version:, page:, entries:)
    transaction do
      entries.map do |entry|
        period = find_or_initialize_by(member_id: entry.fetch(:member_id), period_key: period_key)
        period.assign_attributes(started_on: entry.fetch(:started_on),
          start_source_version: source_version, start_page: page)
        period.save! if period.new_record? || period.changed?
        period
      end
    end
  end

  private

  def end_has_date_and_source
    if [ ended_on, end_source_version_id, end_page ].any?(&:present?)
      errors.add(:ended_on, "needs a date, source and page") unless ended_on && end_source_version && end_page
    end
    if ended_on && started_on && ended_on < started_on
      errors.add(:ended_on, "cannot precede the start")
    end
  end
end
