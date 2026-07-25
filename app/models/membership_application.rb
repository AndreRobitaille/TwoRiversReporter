class MembershipApplication < ApplicationRecord
  STATUSES = %w[email_pending submitted approved rejected].freeze

  belongs_to :user
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :first_name, :last_name, :city, :state, presence: true, unless: :email_pending?

  def email_pending?
    status == "email_pending"
  end
end
