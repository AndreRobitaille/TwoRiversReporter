require "uri"

# Source intake is an editorial exception workflow. Only a verified actual case
# and text explicitly cleared for publication can supply a named public event.
class CouncilFormalSource < ApplicationRecord
  FORMAL_KINDS = %w[complaint notice response decision appeal correction].freeze
  KINDS = FORMAL_KINDS + %w[policy public_comment unknown]

  belongs_to :verified_by, class_name: "User", optional: true
  has_many :reviews, class_name: "CouncilFormalReview", dependent: :restrict_with_exception

  normalizes :title, :case_reference, :reviewing_body, :source_url, with: ->(value) { value.strip }
  normalizes :permitted_text, with: ->(value) { value.gsub(/\r\n?/, "\n").strip }
  validates :title, :case_reference, :reviewing_body, :source_url, :published_on, :permitted_text, presence: true
  validates :title, :case_reference, :reviewing_body, length: { maximum: 180 }
  validates :policy_label, length: { maximum: 180 }
  validates :source_url, uniqueness: true
  validates :record_kind, inclusion: { in: KINDS }
  validates :permitted_text, length: { maximum: 60_000 }
  validate :subject_labels
  validate :public_source_link
  validate :verification
  after_commit :queue_processing, on: %i[create update]

  def subject_names_text
    subject_names.join("\n")
  end

  def subject_names_text=(text)
    self.subject_names = text.to_s.lines.map(&:strip).reject(&:empty?)
  end

  def eligible?
    active? && verified_at.present? && FORMAL_KINDS.include?(record_kind)
  end

  def context
    attributes.slice("case_reference", "reviewing_body", "policy_label", "source_url", "record_kind", "permitted_text", "subject_names")
      .merge("published_on" => published_on&.iso8601)
  end

  def input_key
    CouncilProfiles::ReserveAiSpend.request_digest(context)
  end

  def current_review
    reviews.find_by(input_key: input_key)
  end

  def case_key
    CouncilProfiles::ReserveAiSpend.request_digest(
      case_reference: case_reference.split.join(" ").downcase, reviewing_body: reviewing_body.split.join(" ").downcase)
  end

  private

  def queue_processing
    ExtractCouncilFormalRecordsJob.perform_later(id) if eligible? && !current_review
  end

  def subject_labels
    unless subject_names.is_a?(Array) && subject_names.size.between?(1, 20) && subject_names.uniq == subject_names &&
        subject_names.all? { |name| name.is_a?(String) && name.strip.present? && name.length <= 120 }
      errors.add(:subject_names, "must contain 1–20 distinct source labels for officials named in the case")
    end
  end

  def public_source_link
    uri = URI.parse(source_url.to_s)
    errors.add(:source_url, "must be a public HTTP or HTTPS link without credentials") unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank?
  rescue URI::InvalidURIError
    errors.add(:source_url, "must be a valid public source link")
  end

  def verification
    if verified_at && (!verified_by&.admin? || !verified_by.active_for_authentication? || verified_at > Time.current)
      errors.add(:verified_at, "requires verification by an active administrator")
    end
    if verified_at && !(service_period_keys.is_a?(Array) && service_period_keys.any? &&
        service_period_keys.uniq == service_period_keys && (service_period_keys - CouncilServicePeriod.distinct.pluck(:period_key)).empty?)
      errors.add(:service_period_keys, "must identify the documented Council service this case concerns")
    end
    errors.add(:published_on, "cannot be in the future") if published_on && published_on > Date.current
  end
end
