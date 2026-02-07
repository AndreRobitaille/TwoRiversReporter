class TopicBlocklist < ApplicationRecord
  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_validation :normalize_name

  def normalize_name
    self.name = self.name.to_s.strip.downcase.gsub(/[[:punct:]]/, "").squish
  end
end
