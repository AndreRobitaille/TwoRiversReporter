class CampaignStatementTopic < ApplicationRecord
  belongs_to :campaign_extraction
  belongs_to :campaign_statement
  belongs_to :topic
  attr_readonly :campaign_extraction_id, :campaign_statement_id, :original_topic_id

  validates :original_topic_id, uniqueness: { scope: [ :campaign_extraction_id, :campaign_statement_id ] }
  validate :supported_by_matching

  private

  def supported_by_matching
    stage = campaign_extraction
    statement = campaign_statement
    valid = stage&.purpose == "topic_matching" && stage.status == "completed" && statement&.status == "accepted" &&
      statement.campaign_source_version.id == stage.campaign_source_version_id &&
      stage.data.fetch("matches", []).any? do |match|
        match["sequence"] == statement.sequence && match["status"] == "matched" && match["topic_ids"].include?(original_topic_id)
      end
    errors.add(:base, "requires a supported statement and topic match") unless valid
  end
end
