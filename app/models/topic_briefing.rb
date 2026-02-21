class TopicBriefing < ApplicationRecord
  belongs_to :topic
  belongs_to :triggering_meeting, class_name: "Meeting", optional: true

  validates :headline, presence: true
  validates :generation_tier, presence: true,
    inclusion: { in: %w[headline_only interim full] }
  validates :topic_id, uniqueness: true
end
