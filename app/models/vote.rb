class Vote < ApplicationRecord
  belongs_to :motion
  belongs_to :member

  validates :evidence_basis, inclusion: { in: %w[legacy explicit attendance_derived] }

  validates :value, presence: true, inclusion: { in: %w[yes no abstain absent recused] }
end
