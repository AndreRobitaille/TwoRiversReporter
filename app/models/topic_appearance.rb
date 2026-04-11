class TopicAppearance < ApplicationRecord
  belongs_to :topic
  belongs_to :meeting
  belongs_to :agenda_item, optional: true
  belongs_to :committee, optional: true

  validates :evidence_type, presence: true, inclusion: { in: %w[agenda_item meeting_minutes document_citation] }
  validates :appeared_at, presence: true

  # App-level guard against duplicates — paired with a unique DB index on
  # (topic_id, meeting_id, agenda_item_id). Prevents the race where two
  # AgendaItemTopic#after_create callbacks fire concurrently and both pass
  # the exists? check in create_appearance_and_update_continuity before
  # either inserts.
  validates :topic_id, uniqueness: { scope: [ :meeting_id, :agenda_item_id ] }, if: -> { agenda_item_id.present? }
end
