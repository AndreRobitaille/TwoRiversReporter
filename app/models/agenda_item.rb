class AgendaItem < ApplicationRecord
  belongs_to :meeting
  has_many :agenda_item_documents, dependent: :destroy
  has_many :meeting_documents, through: :agenda_item_documents
end
