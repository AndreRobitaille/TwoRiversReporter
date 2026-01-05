class Member < ApplicationRecord
  has_many :votes, dependent: :destroy
  validates :name, presence: true, uniqueness: true
end
