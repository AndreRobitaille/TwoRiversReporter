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

  def forum_clip_times
    source = campaign_source_version
    return {} unless source.forum? && source.source_url.match?(%r{\Ahttps://(?:www\.)?youtube\.com/watch\?v=[a-zA-Z0-9_-]{11}\z})

    location = data["location"]
    return {} unless location && location["start"] && location["end"]

    segments = source.prepared_transcript.fetch("segments", []).select { |segment| segment["text_start"] && segment["text_end"] }
    answer = segments.find do |segment|
      segment["speaker"] == data["source_name"] && segment["attribution"] == "reviewer_verified" &&
        segment["text_start"] <= location["start"] && segment["text_end"] >= location["end"]
    end
    return {} unless answer

    # Use the nearest caption containing the question before this answer, including audience questions.
    question = segments.reverse_each.find do |segment|
      segment["text_start"] <= answer["text_start"] &&
        data["question"].present? && segment["text"].to_s.include?(data["question"])
    end
    { question: question&.fetch("start_ms", nil), answer: answer["start_ms"] }.compact
  end

  def self.current_for(member)
    current_versions = {}
    where(member: member, status: "accepted", excluded_at: nil)
      .includes(campaign_extraction: { campaign_source_version: :campaign_source })
      .group_by(&:campaign_source_version).flat_map do |version, rows|
        current = current_versions[version.campaign_source_id] ||= version.campaign_source.current_version
        version == current || Campaigns::ReviewedQuestionnaireExcerpt.retained?(rows, current) ? rows : []
      end
      .sort_by { |statement| [ -statement.campaign_source_version.election_on.jd, -statement.campaign_source_version.id, statement.sequence ] }
  end
end
