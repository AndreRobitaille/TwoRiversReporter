class AgendaItem < ApplicationRecord
  belongs_to :meeting
  has_many :agenda_item_documents, dependent: :destroy
  has_many :meeting_documents, through: :agenda_item_documents
  has_many :agenda_item_topics, dependent: :destroy
  has_many :topics, through: :agenda_item_topics
  has_many :motions, dependent: :nullify
end
