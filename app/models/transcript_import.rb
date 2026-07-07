class TranscriptImport < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze

  belongs_to :meeting
  belongs_to :meeting_document, optional: true
  has_one_attached :srt_file

  validates :youtube_url, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :meeting_document_matches_meeting

  scope :recent_first, -> { order(created_at: :desc) }

  def append_step_log!(step:, message:, level: "info", metadata: {})
    with_lock do
      entry = {
        at: Time.current.iso8601,
        level: level,
        step: step,
        message: message,
        metadata: metadata
      }.deep_stringify_keys

      update!(step_logs: Array(step_logs) + [ entry ])
    end
  end

  def mark_running!
    with_lock do
      update!(
        status: "running",
        started_at: Time.current,
        finished_at: nil,
        error_class: nil,
        error_message: nil,
        error_backtrace: nil
      )
    end
  end

  def mark_failed!(error, step:)
    with_lock do
      entry = {
        at: Time.current.iso8601,
        level: "error",
        step: step,
        message: error.message,
        metadata: { error_class: error.class.name }
      }.deep_stringify_keys

      update!(
        status: "failed",
        finished_at: Time.current,
        error_class: error.class.name,
        error_message: error.message,
        error_backtrace: Array(error.backtrace).join("\n"),
        step_logs: Array(step_logs) + [ entry ]
      )
    end
  end

  def mark_completed!(meeting_document:, affected_topic_ids: [])
    with_lock do
      update!(
        status: "completed",
        finished_at: Time.current,
        meeting_document: meeting_document,
        affected_topic_ids: Array(affected_topic_ids).map(&:to_i).uniq.sort,
        error_class: nil,
        error_message: nil,
        error_backtrace: nil
      )
    end
  end

  private

  def meeting_document_matches_meeting
    return if meeting_document.blank?
    return if meeting_document.meeting_id == meeting_id

    errors.add(:meeting_document, "must belong to the same meeting")
  end
end
