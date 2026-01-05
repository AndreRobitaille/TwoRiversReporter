class Motion < ApplicationRecord
  belongs_to :meeting
  belongs_to :agenda_item, optional: true
  has_many :votes, dependent: :destroy
end
