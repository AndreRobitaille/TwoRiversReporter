class AgendaItem < ApplicationRecord
  belongs_to :meeting
  belongs_to :parent, class_name: "AgendaItem", optional: true
  has_many :children, class_name: "AgendaItem", foreign_key: :parent_id, dependent: :nullify
  has_many :agenda_item_documents, dependent: :destroy
  has_many :meeting_documents, through: :agenda_item_documents
  has_many :agenda_item_topics, dependent: :destroy
  has_many :topics, through: :agenda_item_topics
  has_many :motions, dependent: :nullify

  scope :structural, -> { where(kind: "section") }
  scope :substantive, -> { where(kind: [ nil, "item" ]) }
  scope :ordered, -> { order(:order_index) }

  validates :kind, inclusion: { in: %w[section item] }, allow_nil: true
  validate :parent_must_be_valid_for_meeting

  def structural?
    kind == "section"
  end

  def substantive?
    kind.nil? || kind == "item"
  end

  def display_context_title
    return title if parent.blank?

    "#{parent.title} — #{title}"
  end

  private

  def parent_must_be_valid_for_meeting
    return if parent.blank?

    if parent.equal?(self)
      errors.add(:parent, "cannot be self")
      return
    end

    if parent.meeting_id != meeting_id
      errors.add(:parent, "must belong to the same meeting")
    end

    ancestor = parent
    while ancestor.present?
      if ancestor.equal?(self) || (id.present? && ancestor.id == id)
        errors.add(:parent, "cannot create a cycle")
        break
      end

      ancestor = ancestor.parent
    end
  end
end
