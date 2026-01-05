class Meeting < ApplicationRecord
  has_many :meeting_documents, dependent: :destroy
  has_many :agenda_items, dependent: :destroy
  validates :detail_page_url, presence: true, uniqueness: true
end
