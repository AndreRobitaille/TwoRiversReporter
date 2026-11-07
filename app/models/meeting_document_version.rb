require "digest"

# Retained download evidence, not approval of its text or any generated claim.
# Extraction/page versions and reviewed assertions will reference this artifact.
class MeetingDocumentVersion < ApplicationRecord
  belongs_to :meeting_document, optional: true
  has_one_attached :file

  attr_readonly :original_document_id, :version_key, :sha256, :source_url,
    :document_type, :original_meeting_id, :meeting_starts_at, :retrieved_at,
    :source_last_modified, :published_at, :evidence_status, :capture_method

  validates :original_document_id, :original_meeting_id, :source_url,
    :document_type, :retrieved_at, presence: true
  validates :sha256, :version_key, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :version_key, uniqueness: true
  validates :evidence_status, inclusion: { in: [ "collected" ] }
  validates :capture_method, inclusion: { in: [ "download_sha256_v1" ] }
  validate :retained_file_is_immutable

  def self.key_for(document)
    Digest::SHA256.hexdigest(JSON.generate([
      document.id, document.source_url, document.document_type, document.sha256
    ]))
  end

  # Caller holds the document lock and has saved metadata for these exact bytes.
  # Do not capture legacy text as though it was extracted from this new artifact.
  def self.capture!(document, file: document.file.blob)
    find_by(version_key: key_for(document)) || create!(
      meeting_document: document,
      original_document_id: document.id,
      original_meeting_id: document.meeting_id,
      meeting_starts_at: document.meeting.starts_at,
      version_key: key_for(document),
      sha256: document.sha256,
      source_url: document.source_url,
      document_type: document.document_type,
      retrieved_at: document.fetched_at,
      source_last_modified: document.last_modified,
      file: file
    )
  end

  def current?
    document = MeetingDocument.find_by(id: meeting_document_id)
    document.present? && self.class.key_for(document) == version_key
  end

  private

  def retained_file_is_immutable
    errors.add(:file, "must be retained") unless file.attached?
    if persisted? && attachment_changes.key?("file")
      errors.add(:file, "cannot be replaced")
    end
  end
end
