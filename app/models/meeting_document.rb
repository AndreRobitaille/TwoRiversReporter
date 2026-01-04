class MeetingDocument < ApplicationRecord
  belongs_to :meeting
  has_one_attached :file
end
