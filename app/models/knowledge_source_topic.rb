class KnowledgeSourceTopic < ApplicationRecord
  belongs_to :knowledge_source
  belongs_to :topic

  validates :topic_id, uniqueness: { scope: :knowledge_source_id }
end
