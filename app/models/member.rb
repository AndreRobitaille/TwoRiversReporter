class Member < ApplicationRecord
  has_many :votes, dependent: :destroy
  has_many :committee_memberships, dependent: :destroy
  has_many :meeting_attendances, dependent: :destroy
  has_many :committees, through: :committee_memberships
  validates :name, presence: true, uniqueness: true
end
