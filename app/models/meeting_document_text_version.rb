class MeetingDocumentTextVersion < ApplicationRecord
  belongs_to :meeting_document_version

  attr_readonly :meeting_document_version_id, :fingerprint, :extractor_version,
    :evidence_status, :page_count, :text_quality, :extracted_text, :pages

  validates :fingerprint, format: { with: /\A[0-9a-f]{64}\z/ }, uniqueness: true
  validates :extractor_version, :text_quality, presence: true
  validates :evidence_status, inclusion: { in: [ "extracted" ] }
  validates :page_count, numericality: { only_integer: true, greater_than: 0 }
  validate :complete_page_sequence

  private

  def complete_page_sequence
    valid = pages.is_a?(Array) && pages.size == page_count && pages.each_with_index.all? do |page, index|
      page.is_a?(Hash) && page["page_number"] == index + 1 &&
        page["raw_text"].is_a?(String) && page["cleaned_text"].is_a?(String)
    end
    valid &&= extracted_text == pages.map { |page| page["cleaned_text"] }.join(" ")
    errors.add(:pages, "must preserve every page and the complete extracted text") unless valid
  end
end
