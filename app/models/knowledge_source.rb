class KnowledgeSource < ApplicationRecord
  has_many :knowledge_chunks, dependent: :destroy
  has_one_attached :file

  validates :title, presence: true
  validates :source_type, presence: true, inclusion: { in: %w[note pdf] }

  after_save :ingest_later, if: -> { saved_change_to_body? || attachment_changes["file"].present? }

  def ingest_later
    IngestKnowledgeSourceJob.perform_later(id)
  end
end
