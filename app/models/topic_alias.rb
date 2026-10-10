class TopicAlias < ApplicationRecord
  belongs_to :topic

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_validation :normalize_name

  def normalize_name
    self.name = Topic.normalize_name(name)
  end
end
