class StanceObservation < ApplicationRecord
  belongs_to :entity
  belongs_to :meeting
  belongs_to :meeting_document
end
