class Topic < ApplicationRecord
  has_many :agenda_item_topics, dependent: :destroy
  has_many :agenda_items, through: :agenda_item_topics
  validates :name, presence: true, uniqueness: true
end
