class CampaignStatement < ApplicationRecord
  KINDS = { "commitment" => "Commitment", "priority" => "Priority", "position" => "Position", "retrospective_claim" => "Claim about past work" }.freeze

  belongs_to :campaign_extraction
  belongs_to :member, optional: true
  has_many :campaign_statement_topics, dependent: :destroy
  has_many :related_topics, -> { approved.distinct }, through: :campaign_statement_topics, source: :topic
  delegate :campaign_source_version, to: :campaign_extraction
  attr_readonly :campaign_extraction_id, :sequence, :data

  validates :sequence, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, uniqueness: { scope: :campaign_extraction_id }
  validates :status, inclusion: { in: %w[accepted unresolved] }
  validates :validation_method, :validated_at, :data, presence: true
  validates :member, presence: true, if: -> { status == "accepted" }

  def self.current_for(member)
    current_versions = {}
    where(member: member, status: "accepted")
      .includes(campaign_extraction: { campaign_source_version: :campaign_source })
      .select do |statement|
        version = statement.campaign_source_version
        current_versions[version.campaign_source_id] ||= version.campaign_source.current_version&.id
        current_versions[version.campaign_source_id] == version.id
      end
      .sort_by { |statement| [ -statement.campaign_source_version.election_on.jd, -statement.campaign_source_version.id, statement.sequence ] }
  end
end
