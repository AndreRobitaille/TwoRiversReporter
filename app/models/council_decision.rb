class CouncilDecision < ApplicationRecord
  belongs_to :meeting, optional: true
  has_many :assignments, class_name: "CouncilDecisionAssignment", dependent: :restrict_with_exception
  has_many :observations, through: :assignments, source: :observation
  has_many :extracted_observations, class_name: "CouncilDecisionObservation", dependent: :restrict_with_exception
  attr_readonly :original_meeting_id, :public_id

  before_validation -> { self.public_id ||= SecureRandom.uuid }, on: :create
  validates :original_meeting_id, presence: true
  validates :public_id, uniqueness: true, format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/ }

  # A stable reference never silently falls back to a superseded observation.
  def current_observation
    CouncilDecisionObservation.joins(identity_assignment: { council_decision: { meeting: :minutes_publication } })
      .where(council_decisions: { id: id })
      .where("council_decision_assignments.minutes_extraction_id = minutes_publications.votes_extraction_id").take
  end
end
