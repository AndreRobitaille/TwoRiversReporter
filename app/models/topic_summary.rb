class TopicSummary < ApplicationRecord
  belongs_to :topic
  belongs_to :meeting

  validates :content, presence: true
  validates :summary_type, presence: true
  validates :generation_data, presence: true # Should be at least {} due to default, but ensures structure
end
