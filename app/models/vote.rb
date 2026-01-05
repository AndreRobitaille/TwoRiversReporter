class Vote < ApplicationRecord
  belongs_to :motion
  belongs_to :member

  validates :value, presence: true, inclusion: { in: %w[yes no abstain absent recused] }
end
