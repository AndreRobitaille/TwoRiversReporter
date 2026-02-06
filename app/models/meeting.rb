class Meeting < ApplicationRecord
  has_many :meeting_documents, dependent: :destroy
  has_many :agenda_items, dependent: :destroy
  has_many :meeting_summaries, dependent: :destroy
  has_many :motions, dependent: :destroy

  validates :detail_page_url, presence: true, uniqueness: true

  def document_status
    # Avoid N+1 queries if loaded, otherwise load
    docs = association(:meeting_documents).loaded? ? meeting_documents : meeting_documents.load

    if docs.any? { |d| d.document_type == "minutes_pdf" }
      :minutes
    elsif docs.any? { |d| d.document_type == "packet_pdf" }
      :packet
    elsif docs.any? { |d| d.document_type == "agenda_pdf" }
      :agenda
    else
      :none
    end
  end
end
