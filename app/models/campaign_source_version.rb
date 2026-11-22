class CampaignSourceVersion < ApplicationRecord
  belongs_to :campaign_source
  belongs_to :submitted_by, class_name: "User", optional: true
  has_one :extraction, -> { where(purpose: "statements") }, class_name: "CampaignExtraction", dependent: :restrict_with_exception
  has_one :topic_matching, -> { where(purpose: "topic_matching") }, class_name: "CampaignExtraction", dependent: :restrict_with_exception

  attr_readonly(*CampaignSource::SNAPSHOT_FIELDS, :campaign_source_id, :version_key, :content_sha256, :submitted_by_id)
  validates :version_key, :content_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :version_key, uniqueness: true

  def forum?
    prepared_transcript.present?
  end
end
