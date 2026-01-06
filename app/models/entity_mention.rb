class EntityMention < ApplicationRecord
  belongs_to :entity
  belongs_to :meeting
  belongs_to :meeting_document
end
