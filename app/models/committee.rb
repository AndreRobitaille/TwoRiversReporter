class Committee < ApplicationRecord
  has_many :committee_aliases, dependent: :destroy
  has_many :committee_memberships, dependent: :destroy
  has_many :members, through: :committee_memberships
  has_many :meetings, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  validates :committee_type, inclusion: { in: %w[city tax_funded_nonprofit external] }
  validates :status, inclusion: { in: %w[active dormant dissolved] }

  before_validation :generate_slug

  scope :active, -> { where(status: "active") }
  scope :dormant, -> { where(status: "dormant") }
  scope :for_ai_context, -> { where(status: %w[active dormant]).where.not(description: [nil, ""]).order(:name) }

  def self.resolve(body_name)
    return nil if body_name.blank?
    find_by(name: body_name) || CommitteeAlias.find_by(name: body_name)&.committee
  end

  private

  def generate_slug
    self.slug = name.parameterize if name.present? && (slug.blank? || name_changed?)
  end
end
