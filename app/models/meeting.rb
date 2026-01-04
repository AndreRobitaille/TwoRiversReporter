class Meeting < ApplicationRecord
  has_many :meeting_documents, dependent: :destroy
  validates :detail_page_url, presence: true, uniqueness: true
end
